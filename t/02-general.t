#!/usr/local/bin/perl
use warnings;
use strict;

use Test::More tests => 33;
use Data::Dumper;
use Config::Ini;

my $ini_data = do{ local $/; <DATA> };

Init_vs_New: {

    my $data = $ini_data;

    my $ini1 = Config::Ini->new( string => $data );
    my $dump1 = Dumper $ini1;

    my $ini2 = Config::Ini->new();
    $ini2->init( string => $data );
    my $dump2 = Dumper $ini2;

    is( $dump1, $dump2, 'init() vs new()' );

}

Get_Methods: {

    my $data = $ini_data;

    my $ini = Config::Ini->new( string => $data );

    my @sections = $ini->get_sections();
    is( "@sections", ' section1 section2',  # initial blank for 'null' section
        'get_sections()' );

    my @names = map { $ini->get_names( $_ ) } @sections;
    is( "@names", 'name0.1 name0.2 name1.1 name1.2 name2.1 name2.2 name2.3 name2.4',
        'get_names()' );

    @names = $ini->get_names( "" );
    is( "@names", 'name0.1 name0.2',
        'get_names()' );

    @names = $ini->get_names();  # should be same as get_names( "" )
    is( "@names", 'name0.1 name0.2',
        'get_names()' );

    is( $ini->get( 'name0.1' ), 'value0.1',
        'get( name )' );

    is( $ini->get( "" => 'name0.2', 0 ), 'value0.2',
        'get( "", name, 0 )' );

    is( $ini->get( section1 => 'name1.1', 0 ), 'value1.1',
        'get( section, name, 0 )' );

    is( $ini->get( section1 => 'name1.2', 1 ), 'value1.2b',
        'get( section, name, i )' );

    my @values = $ini->get( section2 => 'name2.1' );
    is( "@values", "value2.1\n",
        'get( section, name ) (heredoc)' );

    @values = $ini->get( section2 => 'name2.2' );
    is( "@values", "value2.2\nvalue2.2",
        'get( section, name ) (heredoc :chomp)' );

    @values = $ini->get( section2 => 'name2.3' );
    is( "@values", "value2.3value2.3\n",
        'get( section, name ) (heredoc :join)' );

    @values = $ini->get( section2 => 'name2.4' );
    is( "@values", "value2.4 value2.4",
        'get( section, name ) (heredoc :parse)' );


}

Add_Set_Put_Methods: {

    my $data = $ini_data;
    my $ini = Config::Ini->new( string => $data );

    $ini->add( section3 => 'name3.1', 'value3.1' );
    is( $ini->get( section3 => 'name3.1' ), 'value3.1',
        'add( section, name, value )' );

    $ini->add( section4 => 'name4.1', 'value4.1' );
    is( $ini->get( section4 => 'name4.1' ), 'value4.1',
        'add( section(new), name, value )' );

    $ini->set( section3 => 'name3.1', 0, 'value_3_1' );
    is( $ini->get( section3 => 'name3.1' ), 'value_3_1',
        'set( section, name, value )' );

    $ini->set( section3 => 'name3.1', 1, 'value_3_2' );
    is( $ini->get( section3 => 'name3.1' ), 'value_3_1 value_3_2',
        'set( section, name, value )' );

    $ini->put( section3 => 'name3.1', 'value3.1' );
    is( $ini->get( section3 => 'name3.1' ), 'value3.1',
        'put( section, name, value )' );

}

Delete_Methods: {

    my $as_string = sub {
        my( $ini ) = @_; my $ret = '';
        for my $s ( $ini->get_sections() )  { $ret .= "[$s]";
        for my $n ( $ini->get_names( $s ) ) { $ret .= "($n)";
        for my $v ( $ini->get( $s, $n ) )   { $ret .= "<$v>" } } }
        $ret;
    };

    my $data = <<'__';
n01=v01
n02=v02
n03=v03
[s1]
n11=v11
n12=v12
[s2]
n21=v21
n22=v22
__

    my $ini = Config::Ini->new( string => $data );
    is( $as_string->( $ini ),
        '[](n01)<v01>(n02)<v02>(n03)<v03>[s1](n11)<v11>(n12)<v12>[s2](n21)<v21>(n22)<v22>',
        "delete methods init" );

    $ini->delete_name( '', 'n01' );
    is( $as_string->( $ini ),
        '[](n02)<v02>(n03)<v03>[s1](n11)<v11>(n12)<v12>[s2](n21)<v21>(n22)<v22>',
        "delete_name( '', 'n01' )" );

    $ini->delete_name( 'n02' );
    is( $as_string->( $ini ),
        '[](n03)<v03>[s1](n11)<v11>(n12)<v12>[s2](n21)<v21>(n22)<v22>',
        "delete_name( 'n02' )" );

    $ini->delete_name( 's1', 'n11' );
    is( $as_string->( $ini ),
        '[](n03)<v03>[s1](n12)<v12>[s2](n21)<v21>(n22)<v22>',
        "delete_name( 's1', 'n11' )" );

    $ini->delete_section( '' );
    is( $as_string->( $ini ),
        '[s1](n12)<v12>[s2](n21)<v21>(n22)<v22>',
        "delete_section( '' )" );

    $ini = Config::Ini->new( string => $data );
    $ini->delete_section();
    is( $as_string->( $ini ),
        '[s1](n11)<v11>(n12)<v12>[s2](n21)<v21>(n22)<v22>',
        "delete_section()" );

    $ini->delete_section( 's2' );
    is( $as_string->( $ini ),
        '[s1](n11)<v11>(n12)<v12>',
        "delete_section( 's2' )" );

}

Attributes: {

    my $data = $ini_data;
    my %defaults = (
        file => undef,
    );

    for my $attr ( keys %defaults ) {

        my $ini = Config::Ini->new( string => $ini_data );
        is( $ini->_attr( $attr ), $defaults{ $attr },
            "_attr( $attr ) (default)" );

        is( $ini->_attr( $attr, 1 ), 1, "_attr( $attr, 1 ) (set)" );
        is( $ini->_attr( $attr    ), 1, "_attr( $attr ) (get)" );

    }

    my $ini = Config::Ini->new( string => $ini_data, file => 'acme.ini' );
    is( $ini->file(), 'acme.ini', "file()" );
    is( $ini->file( 'acme.ini' ), 'acme.ini' , "file()" );
    is( $ini->file( undef ), undef , "file()" );
    eval { $ini->you_dont_know_me( 1 ); };
    ok ( $@ =~ /^Undefined: you_dont_know_me()/, "undefined sub()" );
}

Heredoc_Bugfix: {

    # before the fix, this was seen as
    # "name = This is a" = {test
    # and was an unterminated heredoc
    # after the fix, it's DWIM, i.e.,
    # "name" = "This is a = {test"

    my $string = <<__;
[section]
name = This is a = {test
__

    my $ini = Config::Ini->new( string => $string );
    ok( $ini, "heredoc bugfix, new() didn't die" );
}

__DATA__
# 'null' section
name0.1 = value0.1
name0.2 = value0.2

# Section 1

[section1]

# Name 1.1
name1.1 = value1.1

# Name 1.2a
name1.2 = value1.2a
# Name 1.2b
name1.2 = value1.2b

# Section 2

[section2]

# Name 2.1

name2.1 = {
value2.1
}
name2.2 = <<:chomp
value2.2
value2.2
<<
name2.3 = {here :join
value2.3
value2.3
}here
name2.4 = <<here :parse(\n)
value2.4
value2.4
<<here
