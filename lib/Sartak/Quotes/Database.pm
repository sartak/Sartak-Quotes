package Sartak::Quotes::Database;
use 5.14.0;
use Moose;
use DBI;

use Sartak::Quotes::Post;
use Sartak::Quotes::Feed;

has file => (
    reader   => '_file',
    isa      => 'Str',
    required => 1,
);

has dbh => (
    reader  => '_dbh',
    lazy    => 1,
    builder => '_build_dbh',
    handles => {
        _prepare => 'prepare',
        _do      => 'do',
    },
);

sub _build_dbh {
    my $self = shift;
    my $needs_schema = !-e $self->_file;

    my $dbh = DBI->connect("dbi:SQLite:dbname=" . $self->_file);
    $dbh->{sqlite_unicode} = 1;

    if ($needs_schema) {
        $self->schematize($dbh);
    }

    return $dbh;
}

sub schematize {
    my $self = shift;
    my $dbh  = shift;

    $dbh->do(<< '    SCHEMA');
CREATE TABLE posts (
    created INTEGER,
    date TEXT NOT NULL,
    text TEXT NOT NULL,
    author TEXT NOT NULL,
    source TEXT NOT NULL,
    source_url TEXT
);
    SCHEMA
}

sub insert_post {
    my $self = shift;
    my $post = shift;

    $self->_do("INSERT INTO posts (created, date, text, author, source, source_url) values (?, ?, ?, ?, ?, ?);", {},
        $post->created,
        $post->date,
        $post->text,
        $post->author,
        $post->source,
        $post->source_url,
    );

    return $self->_dbh->last_insert_id(undef, undef, "posts", undef);
}

sub authors {
    my $self = shift;

    my $query = "SELECT author, COUNT(rowid) FROM posts GROUP BY author ORDER BY COUNT(rowid) DESC, author ASC;";

    my $sth = $self->_prepare($query);
    $sth->execute;

    my @authors;
    while (my ($author, $count) = $sth->fetchrow_array) {
        push @authors, {
            name  => $author,
            count => $count,
        };
    }

    return @authors;
}

sub feed {
    my $self = shift;
    my %args = @_;

    my $query = "SELECT rowid, created, date, text, author, source, source_url FROM posts ";
    my @where;
    my @bind;

    if ($args{author}) {
        push @where, "author=?";
        push @bind, $args{author};
    }

    if ($args{before}) {
        push @where, "rowid<?";
        push @bind, $args{before};
    }

    if (@where) {
        $query .= "WHERE " . join(' AND ', @where);
    }

    $query .= "ORDER BY created DESC ";
    $query .= "LIMIT 21 ";
    $query .= ";";

    my $sth = $self->_prepare($query);
    $sth->execute(@bind);

    my @posts;
    while (my ($rowid, $created, $date, $text, $author, $source, $source_url) = $sth->fetchrow_array) {
        my $post = Sartak::Quotes::Post->new(
            rowid      => $rowid,
            created    => $created,
            date       => $date,
            text       => $text,
            author     => $author,
            source     => $source,
            source_url => $source_url,
        );
        push @posts, $post;
    }

    my $has_more = 0;
    if (@posts == 21) {
        pop @posts;
        $has_more = 1;
    }

    return Sartak::Quotes::Feed->new(
        title    => $args{title},
        context  => $args{context},
        posts    => \@posts,
        has_more => $has_more,
    );
}

sub post {
    my $self  = shift;
    my $rowid = shift;

    my $query = "SELECT rowid, created, date, text, author, source, source_url FROM posts WHERE rowid=?;";
    my @bind = ($rowid);

    my $sth = $self->_prepare($query);
    $sth->execute(@bind);

    my @posts;
    if (my ($rowid, $created, $date, $text, $author, $source, $source_url) = $sth->fetchrow_array) {
        my $post = Sartak::Quotes::Post->new(
            rowid      => $rowid,
            created    => $created,
            date       => $date,
            text       => $text,
            author     => $author,
            source     => $source,
            source_url => $source_url,
        );
        return $post;
    }

    return;
}

sub update_post {
    my $self = shift;
    my $post = shift;
    my $cols = shift;

    my $query = "UPDATE posts SET ";
    my @bind;

    for my $col (keys %$cols) {
        $query .= "$col=? ";
        push @bind, $cols->{$col};
    }

    $query .= "WHERE rowid=?;";
    push @bind, $post->rowid;

    my $ok = $self->_do($query, {}, @bind);
    return $ok;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

