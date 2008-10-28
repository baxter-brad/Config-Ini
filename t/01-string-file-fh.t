#!/usr/local/bin/perl
use warnings;
use strict;

use Test::More tests => 7;
use File::Temp qw/ tempfile tempdir /;

BEGIN { use_ok('Config::Ini') };
my $ini_data = do{ local $/; <DATA> };

# make a temporary ini file
my $dir = tempdir( CLEANUP => 1 );
my ( $fh, $filename ) = tempfile( DIR => $dir );
print $fh $ini_data;
close $fh;

# simple stringifier for testing
sub as_string {
    my( $ini ) = @_;
    my $output = '';
    for my $section ( $ini->get_sections() ) {
        $output .= "$section\n";

        for my $name ( $ini->get_names( $section ) ) {
            $output .= "  $name\n";

            for my $value ( $ini->get( $section, $name ) ) {
                $output .= "    $value\n";
            }
        }
    }
    $output;
}

my $sample = <<'__';
section1
  name1.1
    value1.1
  name1.2
    value1.2a
    value1.2b
section2
  name2.1
    value2.1

    value2.1
value2.1
__


String: {

    my $data = $ini_data;

    my $ini = Config::Ini->new( string => $data );
    ok( defined $ini, 'new( string )' );

    my $output = as_string( $ini );
    is( $output, $sample, 'loaded ok' );

}

File: {

    my $ini = Config::Ini->new( file => $filename );
    ok( defined $ini, 'new( file )' );

    my $output = as_string( $ini );
    is( $output, $sample, 'loaded ok' );

}

FH: {

    open my $FH, '<', $filename or die "Can't open $filename: $!";
    my $ini = Config::Ini->new( fh => $FH );
    ok( defined $ini, 'new( fh )' );

    my $output = as_string( $ini );
    is( $output, $sample, 'loaded ok' );

}

__DATA__
# Section 1

[section1]

# Name 1.1
name1.1 = value1.1

# Name 1.2
name1.2 = value1.2a
name1.2 = value1.2b

# Section 2

[section2]

# Name 2.1
name2.1 = {
value2.1
}

name2.1 = {:chomp
value2.1
value2.1
}
