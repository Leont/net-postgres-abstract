use v6.d;

unit class Net::Postgres::Abstract;

use Net::Postgres;
use SQL::Abstract;

my package EXPORT::functions {
	our &value = &SQL::Abstract::value;
	our &delegate = &SQL::Query::delegate;
	our &delegate-pair = &SQL::Query::delegate-pair;
	our &delegate-pairs = &SQL::Query::delegate-pairs;
}

has Net::Postgres::Connection:D $!connection is built is required handles<disconnected add-enum-type add-composite-type add-custom-type terminate get-parameter process-id query-status listen transaction>;
has SQL::Abstract:D $!abstract = SQL::Abstract.new(:placeholders<postgres>, :quoting);

method connect-tcp(|args --> Promise) {
	Net::Postgres::Connection.connect-tcp(|args).then: -> $p {
		my $connection = await $p;
		self.bless(:$connection);
	}
}

method connect-local(|args --> Promise) {
	Net::Postgres::Connection.connect-local(|args).then: -> $p {
		my $connection = await $p;
		self.bless(:$connection);
	}
}

method connect(|args --> Promise) {
	Net::Postgres::Connection.connect(|args).then: -> $p {
		my $connection = await $p;
		self.bless(:$connection);
	}
}

class PreparedStatement {
	has Net::Postgres::PreparedStatement:D $!statement is built is required handles<columns close>;
	has SQL::Query:D $!query is built is required;

	method execute(%replacements? --> Promise) {
		my @arguments = $!query.resolve(%replacements);
		$!statement.execute(@arguments);
	}
}

method !query(SQL::Query $query, Bool $prepare --> Promise) {
	if $prepare {
		$!connection.prepare($query.sql).then: -> $p {
			my $statement = await $p;
			PreparedStatement.new(:$statement, :$query);
		}
	} else {
		$!connection.query($query.sql, $query.arguments);
	}
}

multi method query(SQL::Query $query) {
	$!connection.query($query.sql, $query.arguments);
}
multi method query(Str $sql, @arguments?) {
	$!connection.query($sql, @arguments);
}
multi method query(SQL::Abstract::Expression $expression) {
	my $query = $!abstract.render($expression);
	$!connection.query($query.sql, $query.arguments);
}

multi method prepare(Str $sql) {
	$!connection.prepare($sql);
}
multi method prepare(Str $sql, @delegate-names) {
	my @arguments = @delegate-names.map(&SQL::Query::delegate);
	my $query = SQL::Query.new($sql, @arguments);
	self!query($query, True);
}

method select(Bool :$prepare, |args --> Promise) {
	self!query($!abstract.select(|args), $prepare);
}

method insert(Bool :$prepare, |args --> Promise) {
	self!query($!abstract.insert(|args), $prepare);
}

method update(Bool :$prepare, |args --> Promise) {
	self!query($!abstract.update(|args), $prepare);
}

method delete(Bool :$prepare, |args --> Promise) {
	self!query($!abstract.delete(|args), $prepare);
}

method values(Bool :$prepare, |args --> Promise) {
	self!query($!abstract.values(|args), $prepare);
}

=begin pod

=head1 NAME

Net::Postgres::Abstract - Abstractly and asynchronously querying your postgresql database

=head1 SYNOPSIS

=begin code :lang<raku>

use Net::Postgres::Abstract;

my $dbh = await Net::Postgres::Abstract.connect-tcp(:$host, :user, :$password);

await $dbh.transaction: {
	my $row = await $dbh.insert('table', { :user<leont>, :language<raku> }, :returning<id>);
	...
}

my $results = await $dbh.select('table', <user password country>, { :age('>' => 25) });
for $results.objects(User) -> $user {
	...
}

my $sth = await $dbh.select('table', *, { :id(delegate('id')) }, :prepare);
for @ids -> $id {
	my $row = await $sth->execute(:$id);
	...
}

=end code

=head1 Description

Net::Postgres::Abstract is at its core a combination of query builder C<SQL::Abstract> and postgresql client C<Net::Postgres>.

=head2 Rationale

=item1 Abstract

It abstracts the generation of SQL queries, so you don't have to write them yourself.

=item1 Asynchronous

All queries are performed asynchronously.

=item1 Prepared

Full support for prepared queries, including named substitution, is offered.

=head1 Constructors

=head2 connect-tcp(--> Promise)

This creates a promise to a new C<Net::Postgres::Abstract> client. It takes the following named arguments:

=item1 Str :$host = 'localhost'

=item1 Int :$port = 5432

=item1 Str :$user = ~$*USER

=item1 Str :password

=item1 Str :$database

=item1 TypeMap :$typemap = Protocol::Postgres::TypeMap::JSON

=item1 Bool :$tls = False

=item1 :%tls-args = ()

=head2 connect-local(--> Promise)

This creates a new C<Net::Postgres::Abstract> client much like C<connect-tcp>, but does so via a unix domain socket.

=item1 IO(Str) :$path = '/var/run/postgresql/'.IO

=item1 Int :$port = 5432

=item1 Str :$user = ~$*USER

=item1 Str :password

=item1 Str :$database

=item1 TypeMap :$typemap = Protocol::Postgres::TypeMap::JSON

=head2 connect(--> Promise)

This takes the same arguments as C<connect-local> and C<connect-tcp>. It will call the former if the C<$host> is localhost and the C<$path> exists, otherwise it will call C<connect-tcp>.


=head1 Querying methods

All these methods return a Promise. if a C<:$prepared> argument is given to them the Promise will contain a C<Net::Postgres::Abstract::PreparedStatement> object, otherwise it will be the usual C<Net::Postgres> return type (usually a C<Net::Postgres::ResultSet> if it returns rows, or a C<Str> if it doesn't).

=head2 select

=begin code :lang<raku>

method select(Source(Any) $source, Column::List(Any) $columns = *, Conditions(Any) $where?, Common(Any) :$common,
Distinction(Any) :$distinct, GroupBy(Any) :$group-by, Conditions(Any) :$having, Window::Clauses(Any) :$windows,
Compound(Pair) :$compound, OrderBy(Any) :$order-by, Int :$limit, Int :$offset, Locking(Any) :$locking)

=end code

This will generate a C<SELECT> query. It will select C<$columns> from C<$source>, filtering by $conditions.

=begin code :lang<raku>

my $join = { :left<books>, :right<authors>, :using<author_id> };
my $result = $abstract.select($join, ['books.name', 'authors.name'], { :cost('<' => 10) });
# SELECT books.name, authors.name FROM books INNER JOIN authors USING (author_id) WHERE cost < 10

my $counts = $abstract.select('artists',
    [ 'name', :number(:count(*)) ],
    { :name(like => 'A%') },
    :group-by<name>, :order-by(:number<desc>));
# SELECT name, COUNT(*) as number FROM artists WHERE name LIKE 'A%' GROUP BY name ORDER BY number DESC

=end code

=head2 update

=begin code :lang<raku>

method update(Table(Any) $target, Assigns(Any) $assigns, Conditions(Any) $where?,
Common(Any) :$common, Source(Any) :$from, Column::List(Any) :$returning)

=end code

This will update C<$target> by assigning the columns and values from C<$set> if they match C<$where>, returning C<$returning>.

=begin code :lang<raku>

$abtract.update('artists', { :name('The Artist (Formerly Known as Prince)') }, { :name<Prince> });
# UPDATE artists SET name = 'The Artist (Formerly Known as Prince)' WHERE name = 'Prince'

=end code

=head2 insert

=head3 Map insertion

=begin code :lang<raku>

method insert(Table(Any) $target, Assigns(Any) $values, Common(Any) :$common,
Overriding(Str) :$overriding, Conflicts(Any) :$conflicts, Column::List(Any) :$returning)

=end code

Inserts the values in C<$values> into the table C<$target>, returning the columns in C<$returning>

=begin code :lang<raku>

$abstract.insert('artists', { :name<Metallica> }, :returning(*));
# INSERT INTO artists (name) VALUES ('Metallica') RETURNING *

=end code

=head3 List insertions

=begin code :lang<raku>

method insert(Table(Any) $target, Identifiers(Any) $columns, Rows(List) $rows, Common(Any) :$common,
Overriding(Str) :$overriding, Conflicts(Any) :$conflicts, Column::List(Any) :$returning)

=end code

Insert into C<$target>, assigning each of the values in Rows to a new row in the table. This way one can insert a multitude of rows into a table.

=begin code :lang<raku>

$abstract.insert('artists', ['name'], [ ['Metallica'], ['Motörhead'] ], :returning(*));
# INSERT INTO artists (name) VALUES ('Metallica'), ('Motörhead') RETURNING *

$abstract.insert('artists', List, [ [ 'Metallica'], ], :returning<id>);
# INSERT INTO artists VALUES ('Metallica') RETURNING id

=end code

=head3 Select insertion

=begin code :lang<raku>

method insert(Table(Any) $target, Identifiers(Any) $columns, Select(Map) $select, Common(Any) :$common,
Overriding(Str) :$overriding, Conflicts(Any) :$conflicts, Column::List(Any) :$returning)

=end code

This selects from a (usually different) table, and inserts the values into the table.

=begin code :lang<raku>

$abstract.insert('artists', 'name', { :source<new_artists>, :columns<name> }, :returning(*));
# INSERT INTO artists (name) SELECT name FROM new_artists RETURNING *

=end code

=head2 delete

=begin code :lang<raku>

method delete(Table:D(Any:D) $target, Conditions(Any) $where, Common(Any) :$common,
Source(Any) :$using, Column::List(Any) :$returning)

=end code

This deletes rows from the database, optionally returning their values.

=begin code :lang<raku>

$abstract.delete('artists', { :name<Madonna> });
# DELETE FROM artists WHERE name = 'Madonna'

=end code

=head2 query

=begin code :lang<raku>

method query(Str $sql, @arguments?)
method query(SQL::Query $query)
method query(SQL::Abstract::Expression $query)

=end code

Perform a manual query to the database.

=head2 prepare

=begin code :lang<raku>

method prepare(Str $sql)
method prepare(Str $sql, @names)

=end code

This prepares a raw query. If given C<@names> it will take named parameters on execute, without it will take positional ones.

=head2 transaction

To use a transaction, one can use the C<transaction(&code)> method. It's code reference will act as a wrapper for the transaction. If anything throws an exception out of the callback (e.g. a failed query method), a rollback will be attempted.

=head1 Connection methods

=begin item1
listen(Str $channel-name --> Promise[Supply])

This listens to notifications on the given channel. It returns a C<Promise> to a C<Supply> of C<Notification>s.
=end item1

=begin item1
terminate(--> Nil)

This sends a message to the server to terminate the connection
=end item1

=begin item1
disconnected(--> Promise)

This returns a C<Promise> that will be be kept if the connection or broken to signal the connection is lost.
=end item1

=begin item1
process-id(--> Int)

This returns the process id of the backend of this connection. This is useful for debugging purposes and for notifications.
=end item1

=begin item1
get-parameter(Str $name --> Str)

This returns various parameters, currently known parameters are: C<server_version>, C<server_encoding>, C<client_encoding>, C<application_name>, C<default_transaction_read_only>, C<in_hot_standby>, C<is_superuser>, C<session_authorization>, C<DateStyle>, C<IntervalStyle>, C<TimeZone>, C<integer_datetimes>, and C<standard_conforming_strings>.
=end item1

=head1 PreparedStatement

This class is much like C<Net::>

=head1 Exported functions

Under the C<:functions> tag it exports two helper functions

=begin item1
delegate(Str $name, Any $default-value, Any:U :$type)

=end item1

=begin item1
value(Any $value)
=end item1

=head1 AUTHOR

Leon Timmermans <fawaka@gmail.com>

=head1 COPYRIGHT AND LICENSE

Copyright 2023 Leon Timmermans

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod
