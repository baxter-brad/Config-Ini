#---------------------------------------------------------------------
package Config::Ini;

use 5.008000;
use strict;
use warnings;
use Carp;

=head1 NAME

Config::Ini - ini configuration file processor

=head1 SYNOPSIS

 use Config::Ini;
 
 my $ini = Config::Ini->new( 'file.ini' );
 
 # traverse the values
 for my $section ( $ini->get_sections() ) {
     print "$section\n";
 
     for my $name ( $ini->get_names( $section ) ) {
         print "  $name\n";
 
         for my $value ( $ini->get( $section, $name ) ) {
             print "    $value\n";
         }
     }
 }

=head1 VERSION

VERSION: 0.10

=cut

# more POD follows the __END__

our $VERSION = '0.10';

use Text::ParseWords;

# methods summary:
# $ini = Config::Ini->new( $file )             or
# $ini = Config::Ini->new( file   => $file   ) or
# $ini = Config::Ini->new( fh     => $fh     ) or
# $ini = Config::Ini->new( string => $string )
# $ini->init( $file )             or
# $ini->init( file   => $file   ) or
# $ini->init( fh     => $fh     ) or
# $ini->init( string => $string )
# $ini->get_sections()
# $ini->get_names( $section )
# $ini->get( $section, $name, $i )
# $ini->add( $section, $name, @values )
# $ini->set( $section, $name, $i, $value )
# $ini->put( $section, $name, @values )
# $ini->delete_section( $section )
# $ini->delete_name( $section, $name )
# $ini->_attr( $attribute, $value )
# $ini->_autovivify( $section, $name )

use constant SECTIONS => 0;
use constant SHASH    => 1;
use constant ATTRS    => 2;
use constant NAMES  => 0;
use constant NHASH  => 1;
use constant SCMTS  => 2; # see Config::Ini::Edit
use constant VALS  => 0;
use constant CMTS  => 1;  # see Config::Ini::Edit
use constant VATTR => 2;  # see Config::Ini::Edit

# object structure summary:
#           [
# SECTIONS:     [ 'section1', ],
# SHASH:        {
#                   section1 => [
#     NAMES:            [ 'name1', ],
#     NHASH:            {
#                           name1 => [
#         VALS:                 [ $value1, ],
#(        CMTS:                 [ $comments, ],  )
#(        VATTR:                [ $val_attrs, ], )
#                           ],
#                       },
#(    SCMTS:            [ $comments, $comment ], )
#                   ],
#               },
# ATTRS:        { ... },
#           ],

# autoloaded accessors
use subs qw( file );

#---------------------------------------------------------------------
## $ini = Config::Ini->new( $file )             or
## $ini = Config::Ini->new( file   => $file   ) or
## $ini = Config::Ini->new( fh     => $fh     ) or
## $ini = Config::Ini->new( string => $string )
sub new {
    my ( $class, @parms ) = @_;
    my $self  = [];
    bless $self, $class;
    $self->init( @parms ) if @parms;
    return $self;
}

#---------------------------------------------------------------------
## $ini->init( $file )             or
## $ini->init( file   => $file   ) or
## $ini->init( fh     => $fh     ) or
## $ini->init( string => $string )
sub init {
    my ( $self, @parms ) = @_;

    my ( $file, $fh, $string );
    if( @parms == 1 ) {
        $file   = $parms[0];
    }
    else {
        my %parms = @parms;
        $fh     = $parms{'fh'};
        $string = $parms{'string'};
        $file   = $parms{'file'};
    }
    $self->_attr( file => $file ) if $file;

    unless( $fh ) {
        if( $string ) {
            open $fh, '<', \$string
                or croak "Can't open string: $!"; }
        elsif( $file ) {
            open $fh, '<', $file
                or croak "Can't open $file: $!"; }
        else { croak "Invalid parms" }
    }

    my $section = '';
    my $name = '';
    my $value;

    local *_;
    while( <$fh> ) {
        my $parse = '';

        # comment or blank line
        if( /^\s*[#;]/ or /^\s*$/ ) {
            next;
        }

        # [section]
        if( /^\[([^{}\]]+)\]/ ) {
            $section = $1;
            $self->_autovivify( $section );
            next;
        }  # if

        # <<heredoc
        # Note: name = {xyz} must not be seen as a heredoc
        elsif( /^\s*(.+?)\s*[=:]\s*(<<|{)\s*([^}]*?)\s*$/ ) {
            $name       = $1;
            my $style   = $2;
            my $heretag = $3;

            $value = '';

            my $endtag = $style eq '{' ? '}' : '<<';

            my $indented = ($heretag =~ s/\s*:indented\s*//i ) ? 1 : '';
            my $join     = ($heretag =~ s/\s*:join\s*// )      ? 1 : '';
            my $chomp    = ($heretag =~ s/\s*:chomp\s*//)      ? 1 : '';
            $parse = $1   if $heretag =~ s/\s*:parse\s*\(\s*(.*?)\s*\)\s*//;
            $parse = '\n' if $heretag =~ s/\s*:parse\s*//;
            my $extra = '';  # strip unrecognized modifiers
            $extra .= $1 while $heretag =~ s/\s*(:\w+)\s*//;

            my $found_end;
            while( <$fh> ) {

                if( ( $heretag ne '' and
                    /^\s*(?:$endtag)*\s*\Q$heretag\E\s*$/ ) ||
                    ( $heretag eq '' and
                    /^\s*$endtag\s*$/ ) ) {
                    ++$found_end;
                    last;
                }

                chomp $value if $join;
                s/^\s+//     if $indented;
                $value .= $_;

            }  # while

            die "Didn't find heredoc end tag ($heretag) " .
                "for $section:$name" unless $found_end;

            # ':parse' enables ':chomp', too
            chomp $value if $chomp or $parse ne '';

        }  # elsif (heredoc)

        # name = value
        elsif( /^\s*(.+?)\s*[=:]\s*(.*)$/ ) {
            $name = $1;
            $value = $2;
        }

        # "bare word" (treated as boolean set to true(1))
        else {
            s/^\s+//g; s/\s+$//g;
            $name = $_;
            $value = 1;
        }

        if( $parse ne '' ) {
            $parse = $2 if $parse =~ /^(['"\/])(.*)\1$/; # dumb quotes
            $self->add( $section, $name,
                map { (defined $_) ? $_ : '' }
                parse_line( $parse, 0, $value ) ); }
        else {
            $self->add( $section, $name, $value ); }

    }  # while

}  # end sub init

#---------------------------------------------------------------------
## $ini->get_sections()
sub get_sections {
    my ( $self ) = @_;

    return unless defined $self->[SECTIONS];
    return @{$self->[SECTIONS]};
}

#---------------------------------------------------------------------
## $ini->get_names( $section )
sub get_names {
    my ( $self, $section ) = @_;
    return unless defined $section;

    return unless defined $self->[SHASH]{ $section }[NAMES];
    return @{$self->[SHASH]{ $section }[NAMES]};
}

#---------------------------------------------------------------------
## $ini->get( $section, $name, $i )
sub get {
    my ( $self, $section, $name, $i ) = @_;
    return unless defined $section;
    ( $name = $section, $section = '' ) unless defined $name;

    my $aref = $self->[SHASH]{ $section }[NHASH]{ $name }[VALS];
    return unless $aref;
    return $aref->[ $i ] if defined $i;
    return @$aref if wantarray;
    return @$aref == 1 ? $aref->[ 0 ]: "@$aref";
}

#---------------------------------------------------------------------
## $ini->add( $section, $name, @values )
sub add {
    my ( $self, $section, $name, @values ) = @_;
    return unless defined $section and defined $name and @values;

    $self->_autovivify( $section, $name );
    push @{$self->[SHASH]{ $section }[NHASH]{ $name }[VALS]}, @values;
}

#---------------------------------------------------------------------
## $ini->set( $section, $name, $i, $value )
sub set {
    return unless @_ == 5;
    my ( $self, $section, $name, $i, $value ) = @_;

    $self->_autovivify( $section, $name );
    return $self->[SHASH]{ $section }[NHASH]{ $name }[VALS][$i] =
        $value if defined $value;

    # $value is undef
    splice(
        @{$self->[SHASH]{ $section }[NHASH]{ $name }[VALS][$i]},
        $i, 1 );
    return;
}

#---------------------------------------------------------------------
## $ini->put( $section, $name, @values )
sub put {
    my ( $self, $section, $name, @values ) = @_;
    return unless defined $section and defined $name and @values;

    $self->_autovivify( $section, $name );

    $self->[SHASH]{ $section }[NHASH]{ $name }[VALS] = [ @values ];
}

#---------------------------------------------------------------------
## $ini->delete_section( $section )
sub delete_section {
    my ( $self, $section ) = @_;
    $section = '' unless defined $section;
    return unless defined $self->[SECTIONS];

    @{$self->[SECTIONS]} = grep $_ ne $section,
        @{$self->[SECTIONS]};
    delete $self->[SHASH]{ $section };
}

#---------------------------------------------------------------------
## $ini->delete_name( $section, $name )
sub delete_name {
    my ( $self, $section, $name ) = @_;
    return unless defined $section;
    ( $name = $section, $section = '' ) unless defined $name;
    return unless defined $self->[SHASH]{ $section }[NAMES];

    @{$self->[SHASH]{ $section }[NAMES]} = grep $_ ne $name,
        @{$self->[SHASH]{ $section }[NAMES]};
    delete $self->[SHASH]{ $section }[NHASH]{ $name };
}

#---------------------------------------------------------------------
## AUTOLOAD() (wrapper for _attr())
our $AUTOLOAD;
sub AUTOLOAD {
    my $attribute = $AUTOLOAD;
    $attribute =~ s/.*:://;
    die "Undefined: $attribute()" unless $attribute eq 'file';
    my $self = shift;
    $self->_attr( $attribute, @_ );
}
sub DESTROY {}

#---------------------------------------------------------------------
## $ini->_attr( $attribute, $value )
#  $value = undef to delete attribute
sub _attr {
    my( $self, $attribute ) = ( shift, shift );
    unless( @_ ) {
        return unless defined $self->[ATTRS]{ $attribute };
        return $self->[ATTRS]{ $attribute };
    }
    my $value = shift;
    return $self->[ATTRS]{ $attribute } = $value if defined $value;
    delete $self->[ATTRS]{ $attribute };  # $value is undef
    return;
}

#---------------------------------------------------------------------
## $ini->_autovivify( $section, $name )
sub _autovivify {
    my ( $self, $section, $name ) = @_;

    return unless defined $section;
    unless( $self->[SHASH]{ $section } ) {
        push @{$self->[SECTIONS]}, $section;
        $self->[SHASH]{ $section } = [];
    }

    return unless defined $name;
    unless( $self->[SHASH]{ $section }[NHASH]{ $name } ) {
        push @{$self->[SHASH]{ $section }[NAMES]}, $name
        # XXX? $self->[SHASH]{ $section }[NHASH]{ $name } = [];
    }
}

#---------------------------------------------------------------------
1;

__END__

=head1 DESCRIPTION

This is an ini configuration file processor.

=head2 Terminology

 # comment
 [section]
 name = value

In particular 'name' is the term used to refer to the
named options within the sections.

=head2 Syntax

 # before any sections are defined,
 ; assume section eq ''--the "null section"
 name = value
 name: value

 # comments may begin with # or ;, i.e.,
 ; semicolon is valid comment character

 [section]

 # spaces/tabs around '=' are stripped
 # use heredoc to give a value with leading spaces
 # trailing spaces are left intact
 
 name=value
 name= value
 name =value
 name = value
 name    =    value

 # this is a comment
 [section] # this is a comment
 name = value # this is NOT a comment

 # colon is valid assignment character, too.
 name:value
 name: value
 name :value
 name : value
 name    :    value

 # classic heredoc
 name = <<heredoc
 Heredocs are supported several ways.
 heredoc

 # and because I kept doing this
 name = <<heredoc
 value
 <<heredoc

 # and because who cares what it's called
 name = <<
 value
 <<

 # and "block style" (for vi % support)
 name = {
 value
 }

 # and obscure variations, e.g.,
 name = {heredoc
 value
 heredoc

=head2 Heredoc :modifiers

There are several ways to modify the value
in a heredoc as the ini file is read in (i.e.,
as the object is initialized):

 :chomp    - chomps the last line
 :join     - chomps every line BUT the last one
 :indented - unindents every line (strips leading whitespace)
 :parse    - splits on newline (chomps last line)
 :parse(regex) - splits on regex (still chomps last line)

The :parse modifier uses Text::ParseWords::parse_line(),
so CSV-like parsing is possible.

Modifiers may be stacked, e.g., <<:chomp:join:indented,
in any order (but :parse is performed last).

 # value is "Line1\nLine2\n"
 name = <<
 Line1
 Line2
 <<

 # value is "Line1\nLine2"
 name = <<:chomp
 Line1
 Line2
 <<

 # value is "Line1Line2\n"
 name = <<:join
 Line1
 Line2
 <<

 # value is "Line1Line2"
 name = <<:chomp:join
 Line1
 Line2
 <<

 # value is "  Line1\n  Line2\n"
 name = <<
   Line1
   Line2
 <<

 # - indentations do NOT have to be regular to be unindented
 # - any leading spaces/tabs on every line will be stripped
 # - trailing spaces are left intact, as usual
 # value is "Line1\nLine2\n"
 name = <<:indented
   Line1
   Line2
 <<

 # modifiers may have spaces between
 # value is "Line1Line2"
 name = << :chomp :join :indented
   Line1
   Line2
 <<

 # with heredoc "tag"
 # value is "Line1Line2"
 name = <<heredoc :chomp :join :indented
   Line1
   Line2
 heredoc

The :parse modifier turns a single value into
multiple values, e.g.,

 # :parse is same as :parse(\n)
 name = <<:parse
 value1
 value2
 <<

is the same as,

 name = value1
 name = value2

and

 name = <<:parse(/,\s+/)
 "Tom, Dick, and Harry", Fred and Wilma
 <<

is the same as,

 name = Tom, Dick, and Harry
 name = Fred and Wilma

The :parse modifier chomps only the last line by
default, so include '\n' to parse multiple lines.

 # liberal separators
 name = <<:parse([,\s\n]+)
 "Tom, Dick, and Harry" "Fred and Wilma"
 Martha George, 'Hillary and Bill'
 <<

is the same as,

 name = Tom, Dick, and Harry
 name = Fred and Wilma
 name = Martha
 name = George
 name = Hillary and Bill

Modifiers must follow the heredoc characters '<<' (or '{').
If there is a heredoc tag, e.g., EOT, the modifiers typically
follow it, too.

 # I want "    Hey"
 name = <<EOT:chomp
     Hey
 EOT

=head1 METHODS

=head2 Initialization Methods

=over 8

=item new()

=item new( 'filename' )

=item new( file => 'filename' )

=item new( fh => $filehandle )

=item new( string => $string )

=item new( string => $string, file => 'filename' )

=item new( fh => $filehandle, file => 'filename' )

Create an object with the new() method, e.g.,

  my $ini = Config::Ini->new( 'inifile' );

If you pass any parameters, the init() object will be called.
If you pass only one parameter, it's assumed to be the file
name.  Otherwise, use the named parameters, C<file>, C<fh>,
or C<string> to pass a filename, filehandle (already open),
or string.  The string is assumed to look like the contents
of an ini file.

The parameter, C<fh> takes precedent over C<string> which
is over C<file>.  You may pass C<< file => 'filename' >>
with the other parameters to set the C<file> attribute.

If you do not pass any parameters to new(), you can later
call init() with the same parameters described above.

=item init( 'filename' )

=item init( file => 'filename' )

=item init( fh => $filehandle )

=item init( string => $string )

=item init( string => $string, file => 'filename' )

=item init( fh => $filehandle, file => 'filename' )

 my $ini = Config::Ini->new();
 $ini->init( 'filename' );

=back

=head2 Get Methods

=over 8

=item get_sections()

Use get_sections() to retrieve a list of the sections in the
ini file.  They are returned in the order they appear in the
file.

 my @sections = $ini->get_sections();

If there is a "null section", it will be the first in the
list.

If a section appears twice in a file, it only appears
once in this list.  This implies that ...

 [section1]
 name1 = value
 [section2]
 name2 = value
 [section1]
 name3 = value

is the same as ...

 [section1]
 name1 = value
 name3 = value
 [section2]
 name2 = value

=item get_names( $section )

Use get_names() to retrieve a list of the names in a given
section.

 my @names = $ini->get_names( $section );

They are returned in the order they appear in the
section.

If a name appears twice in a section, it only
appears once in this list.  This implies that ...

 [section]
 name1 = value1
 name2 = value2
 name1 = another

is the same as ...

 [section]
 name1 = value1
 name1 = another
 name2 = value2

=item get( $section, $name )

=item get( $section, $name, $i )

=item get( $name )  (assumes $section eq '')

Use get() to retrieve the value(s) for a given name.
If a name appears more than once in a section, the
values are pushed onto an array, and get() will return
this array of values.

 my @values = $ini->get( $section, $name );

Pass an array subscript as the third parameter to
return only one of the values in this array.

 my $value = $ini->get( $section, $name, 0 ); # get first one
 my $value = $ini->get( $section, $name, 1 ); # get second one
 my $value = $ini->get( $section, $name, -1 ); # get last one

If the ini file lists names at the beginning, before
any sections are given, the section name is assumed to
be the null string ('').  If you call get() with just
one parameter, it is assumed to be a name in this "null
section".  If you want to pass an array subscript, then
you must also pass a null string as the first parameter.

 my @values = $ini->get( $name );         # assumes $section==''
 my $value  = $ini->get( '', $name, 0 );  # get first occurrence
 my $value  = $ini->get( '', $name, -1 ); # get last occurrence

This "null section" concept allows for very simple
configuration files like:

 title = Hello World
 color: blue
 margin: 0

=back

=head2 Add/Set/Put Methods

Here, 'add' implies pushing values onto the end,
'set', modifying a single value, and 'put', replacing
all values at once.

=over 8

=item add( $section, $name, @values )

Use add() to add to the value(s) of an option.  If
the option already has values, the new values will
be added to the end (pushed onto the array).

 $ini->add( $section, $name, @values );

To add to the "null section", pass a null string.

 $ini->add( '', $name, @values );

=item set( $section, $name, $i, $value )

Use set() to assign a single value.  Pass undef to
remove a value altogether.  The $i parameter is the
subscript of the values array to assign to (or remove).

 $ini->set( $section, $name, -1, $value ); # set last value
 $ini->set( $section, $name, 0, undef ); # remove first value

To set a value in the "null section", pass a null
string.

 $ini->set( '', $name, 1, $value ); # set second value

=item put( $section, $name, @values )

Use put() to assign all values at once.  Any
existing values are overwritten.

 $ini->put( $section, $name, @values );

To put values in the "null section", pass a null
string.

 $ini->put( '', $name, @values );

=back

=head2 Delete Methods

=over 8

=item delete_section( $section )

Use delete_section() to delete an entire section,
including all of its options and their values.

 $ini->delete_section( $section )

To delete the "null section", don't
pass any parameters (or pass a null string).

 $ini->delete_section();
 $ini->delete_section( '' );

=item delete_name( $section, $name )

Use delete_name() to delete a named option and all
of its values from a section.

 $ini->delete_name( $section, $name );

To delete an option from the "null section",
pass just the name, or pass a null string.

 $ini->delete_name( $name );
 $ini->delete_name( '', $name );

To delete just some of the values, you can use set() with a
subscript, passing undef to delete that one, or you can
first get them using get(), then modify them (e.g., delete
some).  Finally, use put() to replace the old values with
the modified ones.

=back

=head2 Other Accessor Methods

=over 8

=item file( $value )

Use file() to get or set the C<file> object attribute,
which is intended to be the filename of the ini
file from which the object was created.

 $inifile = $ini->file();  # get the name of the file

If $value is not given, file() returns the value of the
C<file> attribute.  If $value is defined, C<file> is set to
$value.  If $value is given but is undef, the C<file>
attribute is removed.

 $ini->file( 'myfile.ini' );  # change the file name
 $ini->file( undef );  # remove the file attribute

=back

=head1 SEE ALSO

Config::Ini::Edit,
Config::Ini::Expanded,
Config::Ini::Quote,
Config::IniFiles,
Config:: ... (many others)

=head1 AUTHOR

Brad Baxter, E<lt>bmb@mail.libs.uga.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2006 by Brad Baxter

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.7 or,
at your option, any later version of Perl 5 you may have available.

=cut
