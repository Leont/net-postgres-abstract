NAME
====

Net::Postgres::Abstract - Abstractly and asynchronously querying your postgresql database

SYNOPSIS
========

```raku
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
```

Description
===========

Net::Postgres::Abstract is at its core a combination of query builder `SQL::Abstract` and postgresql client `Net::Postgres`.

Rationale
---------

  * Abstract

It abstracts the generation of SQL queries, so you don't have to write them yourself.

  * Asynchronous

All queries are performed asynchronously.

  * Prepared

Full support for prepared queries, including named substitution, is offered.

Constructors
============

connect-tcp(--> Promise)
------------------------

This creates a promise to a new `Net::Postgres::Abstract` client. It takes the following named arguments:

  * Str :$host = 'localhost'

  * Int :$port = 5432

  * Str :$user = ~$*USER

  * Str :password

  * Str :$database

  * TypeMap :$typemap = Protocol::Postgres::TypeMap::JSON

  * Bool :$tls = False

  * :%tls-args = ()

connect-local(--> Promise)
--------------------------

This creates a new `Net::Postgres::Abstract` client much like `connect-tcp`, but does so via a unix domain socket.

  * IO(Str) :$path = '/var/run/postgresql/'.IO

  * Int :$port = 5432

  * Str :$user = ~$*USER

  * Str :password

  * Str :$database

  * TypeMap :$typemap = Protocol::Postgres::TypeMap::JSON

connect(--> Promise)
--------------------

This takes the same arguments as `connect-local` and `connect-tcp`. It will call the former if the `$host` is localhost and the `$path` exists, otherwise it will call `connect-tcp`.

Querying methods
================

All these methods return a Promise. if a `:$prepared` argument is given to them the Promise will contain a `Net::Postgres::Abstract::PreparedStatement` object, otherwise it will be the usual `Net::Postgres` return type (usually a `Net::Postgres::ResultSet` if it returns rows, or a `Str` if it doesn't).

select
------

```raku
method select(Source(Any) $source, Column::List(Any) $columns = *, Conditions(Any) $where?, Common(Any) :$common,
Distinction(Any) :$distinct, GroupBy(Any) :$group-by, Conditions(Any) :$having, Window::Clauses(Any) :$windows,
Compound(Pair) :$compound, OrderBy(Any) :$order-by, Int :$limit, Int :$offset, Locking(Any) :$locking)
```

This will generate a `SELECT` query. It will select `$columns` from `$source`, filtering by $conditions.

```raku
my $join = { :left<books>, :right<authors>, :using<author_id> };
my $result = $abstract.select($join, ['books.name', 'authors.name'], { :cost('<' => 10) });
# SELECT books.name, authors.name FROM books INNER JOIN authors USING (author_id) WHERE cost < 10

my $counts = $abstract.select('artists',
    [ 'name', :number(:count(*)) ],
    { :name(like => 'A%') },
    :group-by<name>, :order-by(:number<desc>));
# SELECT name, COUNT(*) as number FROM artists WHERE name LIKE 'A%' GROUP BY name ORDER BY number DESC
```

update
------

```raku
method update(Table(Any) $target, Assigns(Any) $assigns, Conditions(Any) $where?,
Common(Any) :$common, Source(Any) :$from, Column::List(Any) :$returning)
```

This will update `$target` by assigning the columns and values from `$set` if they match `$where`, returning `$returning`.

```raku
$abtract.update('artists', { :name('The Artist (Formerly Known as Prince)') }, { :name<Prince> });
# UPDATE artists SET name = 'The Artist (Formerly Known as Prince)' WHERE name = 'Prince'
```

insert
------

### Map insertion

```raku
method insert(Table(Any) $target, Assigns(Any) $values, Common(Any) :$common,
Overriding(Str) :$overriding, Conflicts(Any) :$conflicts, Column::List(Any) :$returning)
```

Inserts the values in `$values` into the table `$target`, returning the columns in `$returning`

```raku
$abstract.insert('artists', { :name<Metallica> }, :returning(*));
# INSERT INTO artists (name) VALUES ('Metallica') RETURNING *
```

### List insertions

```raku
method insert(Table(Any) $target, Identifiers(Any) $columns, Rows(List) $rows, Common(Any) :$common,
Overriding(Str) :$overriding, Conflicts(Any) :$conflicts, Column::List(Any) :$returning)
```

Insert into `$target`, assigning each of the values in Rows to a new row in the table. This way one can insert a multitude of rows into a table.

```raku
$abstract.insert('artists', ['name'], [ ['Metallica'], ['Motörhead'] ], :returning(*));
# INSERT INTO artists (name) VALUES ('Metallica'), ('Motörhead') RETURNING *

$abstract.insert('artists', List, [ [ 'Metallica'], ], :returning<id>);
# INSERT INTO artists VALUES ('Metallica') RETURNING id
```

### Select insertion

```raku
method insert(Table(Any) $target, Identifiers(Any) $columns, Select(Map) $select, Common(Any) :$common,
Overriding(Str) :$overriding, Conflicts(Any) :$conflicts, Column::List(Any) :$returning)
```

This selects from a (usually different) table, and inserts the values into the table.

```raku
$abstract.insert('artists', 'name', { :source<new_artists>, :columns<name> }, :returning(*));
# INSERT INTO artists (name) SELECT name FROM new_artists RETURNING *
```

delete
------

```raku
method delete(Table:D(Any:D) $target, Conditions(Any) $where, Common(Any) :$common,
Source(Any) :$using, Column::List(Any) :$returning)
```

This deletes rows from the database, optionally returning their values.

```raku
$abstract.delete('artists', { :name<Madonna> });
# DELETE FROM artists WHERE name = 'Madonna'
```

query
-----

```raku
method query(Str $sql, @arguments?)
method query(SQL::Query $query)
method query(SQL::Abstract::Expression $query)
```

Perform a manual query to the database.

prepare
-------

```raku
method prepare(Str $sql)
method prepare(Str $sql, @names)
```

This prepares a raw query. If given `@names` it will take named parameters on execute, without it will take positional ones.

transaction
-----------

To use a transaction, one can use the `transaction(&code)` method. It's code reference will act as a wrapper for the transaction. If anything throws an exception out of the callback (e.g. a failed query method), a rollback will be attempted.

Connection methods
==================

  * listen(Str $channel-name --> Promise[Supply])

    This listens to notifications on the given channel. It returns a `Promise` to a `Supply` of `Notification`s.

  * terminate(--> Nil)

    This sends a message to the server to terminate the connection

  * disconnected(--> Promise)

    This returns a `Promise` that will be be kept if the connection or broken to signal the connection is lost.

  * process-id(--> Int)

    This returns the process id of the backend of this connection. This is useful for debugging purposes and for notifications.

  * get-parameter(Str $name --> Str)

    This returns various parameters, currently known parameters are: `server_version`, `server_encoding`, `client_encoding`, `application_name`, `default_transaction_read_only`, `in_hot_standby`, `is_superuser`, `session_authorization`, `DateStyle`, `IntervalStyle`, `TimeZone`, `integer_datetimes`, and `standard_conforming_strings`.

PreparedStatement
=================

This class is much like `Net::`

Exported functions
==================

Under the `:functions` tag it exports two helper functions

  * delegate(Str $name, Any $default-value, Any:U :$type)

  * value(Any $value)

AUTHOR
======

Leon Timmermans <fawaka@gmail.com>

COPYRIGHT AND LICENSE
=====================

Copyright 2023 Leon Timmermans

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

