package Sartak::Quotes::Feed;
use 5.14.0;
use Moose;
use utf8::all;

use Sartak::Quotes::Post;

has title => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has context => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has has_more => (
    is       => 'ro',
    isa      => 'Bool',
    required => 1,
);

has posts => (
    traits   => ['Array'],
    reader   => 'posts_ref',
    isa      => 'ArrayRef[Sartak::Quotes::Post]',
    required => 1,
    handles  => {
        has_posts => 'count',
        posts     => 'elements',
        add_post  => 'push',
    },
);

sub as_rss {
    my $self = shift;

    use XML::RSS;
    use Encode 'decode_utf8';

    my $feed = XML::RSS->new(version => '1.0');
    $feed->channel(
        title => $self->title,
        link  => 'http://quotes.sartak.org',
    );

    for my $post ($self->posts) {
        my $short_text = $post->text;
        $short_text =~ s/\A(.{100}\w*).*\z/$1…/s;

        my $url = "http://quotes.sartak.org/quote/" . $post->rowid;

        $feed->add_item(
            title       => $post->author . ': ' . $short_text,
            link        => $url,
            permaLink   => $url,
            description => $post->text,
            dc          => {
                date    => $post->feed_date,
                author  => $post->author,
            },
        );
    };

    return $feed->as_string;
}

sub last_post_id {
    my $self = shift;
    return undef unless $self->has_posts;
    return ($self->posts)[-1]->rowid;
}

sub previous_link {
    my $self = shift;
    my $id = $self->last_post_id
        or return undef;

    return $self->context . "before/" . $id;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

