package Sartak::Quotes::Post;
use 5.14.0;
use Moose;

has rowid => (
    is  => 'ro',
    isa => 'Int',
);

has date => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has text => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has author => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has source => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has source_url => (
    is  => 'ro',
    isa => 'Str',
);

has created => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

sub feed_date {
    my $self = shift;

    use DateTime;
    my $dt = DateTime->from_epoch(epoch => $self->created);

    return $dt->strftime('%a, %d %b %Y %T %Z');
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

