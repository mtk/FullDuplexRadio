#!/usr/bin/env raku
use v6;

use HTTP::UserAgent;
use XML;
use Text::CSV;

my constant URL = 'https://fullduplexradio.us/feed.xml';

sub normalize(Str $s --> Str) {
    $s.subst('—', 'a', :g).trim;
}

# Fetch raw bytes and explicitly decode UTF-8.
my $ua = HTTP::UserAgent.new;
my $response = $ua.get(URL, :bin);

unless $response.is-success {
    note "HTTP error: " ~ $response.status-line;
    exit 1;
}

my $document = from-xml(
    $response.content.decode('utf-8')
);

my $csv = Text::CSV.new;
my Int $count = 0;

say 'artist,song';

# Find all description elements in the XML document.
for $document.root.lookfor(:TAG<description>) -> $description {

    # Decode XML text and preserve CDATA content.
    my $content = $description.nodes.map(-> $node {
        given $node {
            when XML::Text  { .string }
            when XML::CDATA { .data }
            default         { '' }
        }
    }).join('');

    # Each description may contain multiple songs.
    for $content.lines -> $raw {
        my $line = $raw.trim;
        my $paren = $line.index(') ');

        next unless $line.starts-with('(')
            && $paren.defined;

        my $timestamp = $line.substr(1, $paren - 1);

        next unless $timestamp ~~
            /^ \d+ ':' \d\d ':' \d\d $/;

        my $entry = $line.substr($paren + 2);

        # Prefer an em dash over an ASCII hyphen.
        my $dash = $entry.index(' — ');
        my $separator = ' — ';

        unless $dash.defined {
            $dash = $entry.index(' - ');
            $separator = ' - ';
        }

        next unless $dash.defined;

        my $artist = normalize(
            $entry.substr(0, $dash)
        );

        my $song = normalize(
            $entry.substr($dash + $separator.chars)
        );

        next unless $artist.chars && $song.chars;

        # Skip DJ commentary.
        next if $artist.starts-with('Your DJ');

        $csv.say($*OUT, [$artist, $song]);
        $count++;
    }
}

note "Wrote $count records";
