#!/usr/bin/env perl
use utf8;
use 5.14.0;
use warnings;

# Xslate with Moose seems to spend a LOT of time cloning objects
BEGIN { $ENV{ANY_MOOSE} = 'Mouse' }

use Plack::Builder;
use Sartak::Quotes::Database;
use Text::Handlebars;
use Encode 'decode_utf8', 'encode_utf8';
use Text::Xslate 'mark_raw';
use Text::Markdown 'markdown';
use HTML::Escape 'escape_html';
use Plack::App::File;
use Plack::Request;
use File::Slurp 'slurp';

use Regexp::Common 'URI';
my $hex      = q<[0-9A-Fa-f]>;
my $escaped  = qq<%$hex$hex>;
my $uric     = q<(?:[-_.!~*'()a-zA-Z0-9;/?:@&=+$,]> . qq<|$escaped)>;
my $fragment = qq<$uric*>;
my $punct    = qq<[.,!?]>;
my $re_uri   = qr[($RE{URI}(?:\#$fragment)?(?<!$punct))];

chomp(my $PASSWORD = slurp '.password');

my $db = Sartak::Quotes::Database->new(file => 'quotes.sqlite');
my $hbs = Text::Handlebars->new(
    path    => ['view'],
    cache   => $ENV{XSLATE_CACHE_LEVEL},
    helpers => {
        json => sub {
            my ($context, $var) = @_;
            require JSON::PP;
            return JSON::PP::encode_json($var);
        },
        format_post_text => sub {
            my ($context, $text) = @_;

            $text =~ s/\n/\n\n/g;
            $text = markdown(escape_html($text));

            $text =~ s{$re_uri}{
                my $link = $1;
                my $ext = substr($link, -4, 4);
                qq[<a href="$link">$link</a>];
            }eg;

            return mark_raw($text);
        },
    },
);

builder {
    mount '/favicon.ico' => sub {
        return [
            302,
            ['Location' => 'http://sartak.org/favicon.ico'],
            [''],
        ];
    };

    mount '/static/' => Plack::App::File->new(root => "view/static/")->to_app;

    mount '/feed/quotes.rss' => sub {
        my $feed = $db->feed(
            title   => "sartak's favorite quotes",
            context => '/feed/quotes.rss',
        );

        return [
            200,
            ['Content-Type' => 'application/rss+xml'],
            [ encode_utf8 $feed->as_rss ],
        ];
    };

    mount '/quote/' => sub {
        my $env = shift;
        if ($env->{PATH_INFO} =~ m{^/(\d+)$}) {
            my $post = $db->post($1);
            if ($post) {
                return [
                    200,
                    ['Content-Type' => 'text/html'],
                    [ encode_utf8 $hbs->render('post', { post => $post }) ],
                ];
            }
        }

        return [
            404,
            [],
            ['Not found'],
        ];
    };

    mount '/before/' => sub {
        my $env = shift;
        if ($env->{PATH_INFO} =~ m{^/(\d+)$}) {
            my $feed = $db->feed(
                title   => "sartak's favorite quotes",
                context => "/",
                before  => $1,
            );

            if ($feed->has_posts) {
                return [
                    200,
                    ['Content-Type' => 'text/html'],
                    [ encode_utf8 $hbs->render('feed', { feed => $feed }) ],
                ];
            }
        }

        return [
            404,
            [],
            ['Not found'],
        ];
    };

    mount '/authors' => sub {
        my $env = shift;

        if ($env->{PATH_INFO} eq '') {
            my @authors = $db->authors;
            return [
                200,
                ['Content-Type' => 'text/html'],
                [ encode_utf8 $hbs->render('authors', { authors => \@authors }) ],
            ];
        }

        return [
            404,
            [],
            ['Not found'],
        ];
    };

    mount '/' => sub {
        my $env = shift;

        if ($env->{PATH_INFO} eq '/') {
            my $feed = $db->feed(
                title   => "sartak's favorite quotes",
                context => '/',
            );

            return [
                200,
                ['Content-Type' => 'text/html'],
                [ encode_utf8 $hbs->render('feed', { feed => $feed }) ],
            ];
        }

        # if ($env->{PATH_INFO} eq '') {
        #     return [
        #         200,
        #         ['Content-Type' => 'text/plain'],
        #         [ '' ],
        #     ];
        # }

        return [
            404,
            [],
            ['Not found'],
        ];
    };

    mount '/author/' => sub {
        my $env = shift;
        if ($env->{PATH_INFO} =~ m{^/([^/]+)$}) {
            my $feed = $db->feed(
                author  => decode_utf8($1),
                title   => "sartak's favorite quotes by $1",
                context => "/author/$1/",
            );

            if ($feed->has_posts) {
                return [
                    200,
                    ['Content-Type' => 'text/html'],
                    [ encode_utf8 $hbs->render('feed', { feed => $feed }) ],
                ];
            }
        }
        elsif ($env->{PATH_INFO} =~ m{^/([^/]+)/before/(\d+)$}) {
            my $feed = $db->feed(
                author  => decode_utf8($1),
                title   => "sartak's favorite quotes by $1",
                context => "/author/$1/",
                before  => $2,
            );

            if ($feed->has_posts) {
                return [
                    200,
                    ['Content-Type' => 'text/html'],
                    [ encode_utf8 $hbs->render('feed', { feed => $feed }) ],
                ];
            }
        }

        return [
            404,
            [],
            ['Not found'],
        ];
    };

    mount '/add' => sub {
        my $req = Plack::Request->new(shift);
        if ($req->method eq 'GET') {
            return [
                200,
                ['Content-Type' => 'text/html'],
                [ encode_utf8 $hbs->render('add') ],
            ];
        }
        elsif ($req->method eq 'POST') {
            unless ($PASSWORD && $req->param('password') eq $PASSWORD) {
                return [
                    401,
                    ['Content-Type' => 'text/plain'],
                    [ "unauthorized" ],
                ];
            }

            my $rowid = eval {
                for (qw/text date author source/) {
                    die "$_ required" unless $req->param($_) =~ /\S/;
                }

                my $post = Sartak::Quotes::Post->new(
                    text       => decode_utf8($req->param('text')),
                    created    => time,
                    date       => decode_utf8($req->param('date')),
                    author     => decode_utf8($req->param('author')),
                    source     => decode_utf8($req->param('source')),
                    source_url => decode_utf8($req->param('source_url')),
                );

                $db->insert_post($post);
            };
            if ($rowid) {
                return [
                    302,
                    ['Location' => "/quote/$rowid"],
                    [ "redirect" ],
                ];
            }
            else {
                return [
                    400,
                    ['Content-Type' => 'text/plain'],
                    [encode_utf8 $@],
                ];
            }
        }
    };
};

