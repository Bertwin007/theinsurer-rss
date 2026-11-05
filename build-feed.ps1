# Builds a local RSS 2.0 file from The Insurer's public sitemap.
# Reads only the sitemap linked from robots.txt. Does not open article pages.
$ErrorActionPreference = "Stop"

$indexUrl = "https://www.theinsurer.com/arc/outboundfeeds/sitemap-index-insurer/?outputType=xml"
$outPath = Join-Path $PSScriptRoot "feed.xml"
$maxItems = 50

$sections = @{
    "ti"                    = "The Insurer"
    "tv"                    = "The Insurer TV"
    "sustainable-insurance" = "Sustainable Insurer"
    "program-manager"       = "Program Manager"
    "cyber-risk"            = "Cyber Risk"
    "parametric-insurer"    = "Parametric Insurer"
    "e-and-s"               = "E&S Insurer"
}

function Get-Xml([string]$url) {
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 40
    $xml = New-Object System.Xml.XmlDocument
    $xml.PreserveWhitespace = $false
    $xml.LoadXml($response.Content)
    return $xml
}

function Get-TitleFromUrl([string]$url) {
    $slug = ([Uri]$url).Segments[-1].Trim("/")
    $slug = $slug -replace "-\d{4}-\d{2}-\d{2}$", ""
    $words = ($slug -replace "-", " ").Trim()
    if (-not $words) { return $url }
    $culture = [cultureinfo]::GetCultureInfo("en-US")
    return $culture.TextInfo.ToTitleCase($words)
}

function Get-Section([string]$url) {
    $segment = ([Uri]$url).Segments | Where-Object { $_ -ne "/" } | Select-Object -First 1
    $key = $segment.Trim("/")
    if ($sections.ContainsKey($key)) { return $sections[$key] }
    return "The Insurer"
}

$index = Get-Xml $indexUrl
$ns = New-Object System.Xml.XmlNamespaceManager($index.NameTable)
$ns.AddNamespace("s", "http://www.sitemaps.org/schemas/sitemap/0.9")
$firstSitemap = $index.SelectSingleNode("//s:sitemap/s:loc", $ns).InnerText

$sitemap = Get-Xml $firstSitemap
$ns2 = New-Object System.Xml.XmlNamespaceManager($sitemap.NameTable)
$ns2.AddNamespace("s", "http://www.sitemaps.org/schemas/sitemap/0.9")
$ns2.AddNamespace("image", "http://www.google.com/schemas/sitemap-image/1.1")

$items = foreach ($node in $sitemap.SelectNodes("//s:url", $ns2)) {
    $loc = $node.SelectSingleNode("s:loc", $ns2).InnerText
    $lastmod = $node.SelectSingleNode("s:lastmod", $ns2).InnerText
    $imageNode = $node.SelectSingleNode("image:image/image:loc", $ns2)
    [pscustomobject]@{
        Link    = $loc
        Updated = [datetimeoffset]::Parse($lastmod)
        Title   = Get-TitleFromUrl $loc
        Section = Get-Section $loc
        Image   = if ($imageNode) { $imageNode.InnerText } else { $null }
    }
}

$items = $items | Sort-Object Updated -Descending | Select-Object -First $maxItems
$latest = ($items | Select-Object -First 1).Updated

$settings = New-Object System.Xml.XmlWriterSettings
$settings.Indent = $true
$settings.Encoding = New-Object System.Text.UTF8Encoding($false)
$writer = [System.Xml.XmlWriter]::Create($outPath, $settings)

$writer.WriteStartDocument()
$writer.WriteStartElement("rss")
$writer.WriteAttributeString("version", "2.0")
$writer.WriteAttributeString("xmlns", "atom", $null, "http://www.w3.org/2005/Atom")
$writer.WriteAttributeString("xmlns", "media", $null, "http://search.yahoo.com/mrss/")

$writer.WriteStartElement("channel")
$writer.WriteElementString("title", "The Insurer")
$writer.WriteElementString("link", "https://www.theinsurer.com/")
$writer.WriteElementString("description", "Latest articles from theinsurer.com, built from the public sitemap. Titles are taken from the article URL.")
$writer.WriteElementString("language", "en")
$writer.WriteElementString("lastBuildDate", $latest.UtcDateTime.ToString("r"))
$writer.WriteStartElement("atom", "link", "http://www.w3.org/2005/Atom")
$writer.WriteAttributeString("href", $outPath)
$writer.WriteAttributeString("rel", "self")
$writer.WriteAttributeString("type", "application/rss+xml")
$writer.WriteEndElement()

foreach ($item in $items) {
    $writer.WriteStartElement("item")
    $writer.WriteElementString("title", $item.Title)
    $writer.WriteElementString("link", $item.Link)
    $writer.WriteElementString("guid", $item.Link)
    $writer.WriteElementString("pubDate", $item.Updated.UtcDateTime.ToString("r"))
    $writer.WriteElementString("category", $item.Section)
    $writer.WriteElementString("description", "$($item.Section) — $($item.Updated.ToString('yyyy-MM-dd'))")
    if ($item.Image) {
        $writer.WriteStartElement("media", "content", "http://search.yahoo.com/mrss/")
        $writer.WriteAttributeString("url", $item.Image)
        $writer.WriteAttributeString("medium", "image")
        $writer.WriteEndElement()
    }
    $writer.WriteEndElement()
}

$writer.WriteEndElement()
$writer.WriteEndElement()
$writer.WriteEndDocument()
$writer.Close()

Write-Output "Wrote $($items.Count) items to $outPath"
$items | Select-Object -First 8 | ForEach-Object {
    Write-Output ("{0:yyyy-MM-dd HH:mm}  [{1}]  {2}" -f $_.Updated, $_.Section, $_.Title)
}
