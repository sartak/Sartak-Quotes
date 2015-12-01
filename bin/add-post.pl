#!/usr/bin/env perl
use 5.14.0;
use warnings;
use Sartak::Quotes::Database;
use Sartak::Quotes::Post;
use Getopt::Whatever;

my $db = Sartak::Quotes::Database->new(
    file => 'quotes.sqlite',
);

my $text = delete($ARGV{text}) or die "text is required";
my $author = delete($ARGV{author}) or die "author is required";
my $source = delete($ARGV{source}) or die "source is required";
my $date = delete($ARGV{date}) or die "date is required";
my $source_url = delete($ARGV{source_url});

die "unexpected parameters: " . join ', ', keys %ARGV
    if %ARGV;

my $post = Sartak::Quotes::Post->new(
    text       => $text,
    created    => time,
    date       => $date,
    author     => $author,
    source     => $source,
    source_url => $source_url,
);

$db->insert_post($post);

