#---------------------------------------------------------------------
package Config::Ini;

use 5.008000;
use strict;
use warnings;
use Carp;

=begin html

 <style type="text/css">
 @import "http://dbsdev.galib.uga.edu/sitegen/css/sitegen.css";
 body { margin: 1em; }
 </style>

=end html

=head1 NAME

Config::Ini - Ini configuration file processor

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

VERSION: 1.00

=cut

# more POD follows the __END__

our $VERSION = '1.00';

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
        if( /^\[([^{}\]]*)\]/ ) {
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
    $section = '' unless defined $section;

    # use 'exists' to avoid autovivification
    return unless exists $self->[SHASH]{ $section };

    return unless defined $self->[SHASH]{ $section }[NAMES];
    return @{$self->[SHASH]{ $section }[NAMES]};
}

#---------------------------------------------------------------------
## $ini->get( $section, $name, $i )
sub get {
    my ( $self, $section, $name, $i ) = @_;
    return unless defined $section;
    ( $name = $section, $section = '' ) unless defined $name;

    # use 'exists' to avoid autovivification
    return unless
        exists $self->[SHASH]{ $section } and
        exists $self->[SHASH]{ $section }[NHASH]{ $name };

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

This is an Ini configuration file processor.

=head2 Terminology

This document uses the terms I<comment>, I<section>, I<name>, and
I<value> when referring to the following parts of the Ini file syntax:

 # comment
 [section]
 name = value

In particular 'name' is the term used to refer to the named options
within the sections.  This terminology is also reflected in method
names, like C<get_sections()> and C<get_names()>.

=head2 Syntax

=head3 The I<null section>

At the top of an Ini file, before any sections have been explicitly
defined, name/value pairs may be defined.  These are assumed to be in
the 'null section', as if an explicit C<[]> line were present.

 # before any sections are defined,
 # assume section eq '', the "null section"
 name = value
 name: value

This 'null section' concept allows for very simple configuration files,
e.g.,

 title = Hello World
 color: blue
 margin: 0

=head3 Comments

Comments may begin with C<'#'> or C<';'>.

 # comments may begin with # or ;, i.e.,
 ; semicolon is valid comment character

Comments may begin on a separate line or may follow section headings.
But they may not follow values.

 # this is a comment
 [section] # this is a comment
 name = value # this is NOT a comment (it is part of the value)

=head3 Assignments

Spaces and tabs around the C<'='> and C<':'> assignment characters are
stripped, i.e., they are not included in the name or value.  Use
heredoc syntax to set a value with leading spaces.  Trailing spaces in
values are left intact.

 [section]
 
 # spaces/tabs around '=' are stripped
 # use heredoc to give a value with leading spaces
 # trailing spaces are left intact
 
 name=value
 name= value
 name =value
 name = value
 name    =    value
 
 # colon is valid assignment character, too.
 name:value
 name: value
 name :value
 name : value
 name    :    value

=head3 Heredocs

Heredoc syntax may be used to assign values that span multiple lines.
Heredoc syntax is supported in more ways than just the classic syntax,
as illustrated below.

 # classic heredoc:
 name = <<heredoc
 Heredocs are supported several ways.
 This is the "classic" syntax, using a
 "heredoc tag" to mark the begin and end.
 heredoc
 
 # ... and the following is supported because I kept doing this
 name = <<heredoc
 value
 <<heredoc
 
 # ... and also the following, because often no one cares what it's called
 name = <<
 value
 <<
 
 # ... and finally "block style" (for vi % support)
 name = {
 value
 }
 
 # ... and obscure variations, e.g.,
 name = {heredoc
 value
 heredoc

That is, the heredoc may begin with C<< '<<' >> or C<'{'> with or
without a tag.  And it may then end with C<< '<<' >> or C<'}'> (with or
without a tag, as it began).  When a tag is used, the ending
C<< '<<' >> or C<'}'> is optional.

=head3 Heredoc :modifiers

There are several ways to modify the value in a heredoc as the Ini file
is read in (i.e., as the object is initialized):

 :chomp    - chomps the last line
 :join     - chomps every line BUT the last one
 :indented - unindents every line (strips leading whitespace)
 :parse    - splits on newline (and chomps last line)
 :parse(regex) - splits on regex (still chomps last line)

The C<':parse'> modifier uses C<Text::ParseWords::parse_line()>, so
CSV-like parsing is possible.

Modifiers may be stacked, e.g., C<< '<<:chomp:join:indented' >> (or
C<< '<<:chomp :join :indented' >>), in any order, but note that
C<':parse'> is performed last.

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
 
 # modifiers may have spaces between them
 # value is "Line1Line2"
 name = << :chomp :join :indented
   Line1
   Line2
 <<
 
 # ... and should come after a heredoc "tag"
 # value is "Line1Line2"
 name = <<heredoc :chomp :join :indented
   Line1
   Line2
 heredoc

The :parse modifier splits a single value into multiple values.  It may
be given with a regular expression parameter to split on other than
newline (the default).

 # :parse is same as :parse(\n)
 name = <<:parse
 value1
 value2
 <<

... is the same as

 name = value1
 name = value2

... and

 name = <<:parse(/,\s+/)
 "Tom, Dick, and Harry", Fred and Wilma
 <<

... is the same as

 name = Tom, Dick, and Harry
 name = Fred and Wilma

The C<':parse'> modifier chomps only the last line, so include C<'\n'>
if needed.

 # liberal separators
 name = <<:parse([,\s\n]+)
 "Tom, Dick, and Harry" "Fred and Wilma"
 Martha George, 'Hillary and Bill'
 <<

... is the same as

 name = Tom, Dick, and Harry
 name = Fred and Wilma
 name = Martha
 name = George
 name = Hillary and Bill

As illustrated above, the enclosing C<'/'> characters around the
regular expression are optional.  You may also use matching quotes
instead, e.g., C<:parse('\s')>.

Modifiers must follow the heredoc characters C<< '<<' >> (or C<'{'>).
If there is a heredoc tag, e.g., C<'EOT'> below, the modifiers should
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

Use new() to create an object, e.g.,

 my $ini = Config::Ini->new( 'inifile' );

If you pass any parameters, the C<init()> method will be called.  If
you pass only one parameter, it's assumed to be the file name.
Otherwise, use the named parameters, C<'file'>, C<'fh'>, or C<'string'>
to pass a filename, filehandle (already open), or string.  The string
is assumed to look like the contents of an Ini file.

The parameter, C<'fh'> takes precedent over C<'string'> which takes
precedent over C<'file'>.  You may pass C<< file => 'filename' >> with
the other parameters to set the C<'file'> attribute.

If you do not pass any parameters to C<new()>, you can later call
C<init()> with the same parameters described above.

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

Use C<get_sections()> to retrieve a list of the sections in the Ini
file.  They are returned in the order they appear in the file.

 my @sections = $ini->get_sections();

If there is a 'null section', it will be the first in the list.

If a section appears twice in a file, it only appears once in this
list.  This implies that ...

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

Use C<get_names()> to retrieve a list of the names in a given section.

 my @names = $ini->get_names( $section );

They are returned in the order they appear in the section.

If a name appears twice in a section, it only appears once in this
list.  This implies that ...

 [section]
 name1 = value1
 name2 = value2
 name1 = another

is the same as ...

 [section]
 name1 = value1
 name1 = another
 name2 = value2

Calling C<get_names()> without a parameter is the same as calling it
with a null string: it retrieves the names from the 'null section'.
The two lines below are equivalent.

 @names = $ini->get_names();
 @names = $ini->get_names( '' );

=item get( $section, $name )

=item get( $section, $name, $i )

=item get( $name )  (assumes $section eq '')

Use C<get()> to retrieve the value or values for a given name.

Note: when an Ini object is initialized, if a name appears more than
once in a section, the values are pushed onto an array, and C<get()>
will return this array of values.

 my @values = $ini->get( $section, $name );

Pass an array subscript as the third parameter to return only one of
the values in this array.

 my $value = $ini->get( $section, $name, 0 );  # get first one
 my $value = $ini->get( $section, $name, 1 );  # get second one
 my $value = $ini->get( $section, $name, -1 ); # get last one

If the Ini file lists names at the beginning, before any sections are
given, the section name is assumed to be a null string ('').  If you
call C<get()> with just one parameter, it is assumed to be a name in
this 'null section'.  If you want to pass an array subscript, then you
must also pass a null string as the first parameter.

 my @values = $ini->get( $name );         # assumes $section eq ''
 my $value  = $ini->get( '', $name, 0 );  # get first occurrence
 my $value  = $ini->get( '', $name, -1 ); # get last occurrence

This "null section" concept allows for very simple configuration files
like:

 title = Hello World
 color: blue
 margin: 0

=back

=head2 Add/Set/Put Methods

Here, I<add> denotes pushing values onto the end, I<set>, modifying a
single value, and I<put>, replacing all values at once.

=over 8

=item add( $section, $name, @values )

Use C<add()> to add to the value or values of an option.  If the option
already has values, the new values will be added to the end (pushed
onto the array).

 $ini->add( $section, $name, @values );

To add to the 'null section', pass a null string.

 $ini->add( '', $name, @values );

=item set( $section, $name, $i, $value )

Use C<set()> to assign a single value.  Pass C<undef> to remove a value
altogether.  The C<$i> parameter is the subscript of the values array
to assign to (or remove).

 $ini->set( $section, $name, -1, $value ); # set last value
 $ini->set( $section, $name, 0, undef );   # remove first value

To set a value in the 'null section', pass a null string.

 $ini->set( '', $name, 1, $value ); # set second value

=item put( $section, $name, @values )

Use C<put()> to assign all values at once.  Any existing values are
overwritten.

 $ini->put( $section, $name, @values );

To put values in the 'null section', pass a null string.

 $ini->put( '', $name, @values );

=back

=head2 Delete Methods

=over 8

=item delete_section( $section )

Use C<delete_section()> to delete an entire section, including all of
its options and their values.

 $ini->delete_section( $section )

To delete the 'null section', don't pass any parameters or pass a null
string.

 $ini->delete_section();
 $ini->delete_section( '' );

=item delete_name( $section, $name )

Use C<delete_name()> to delete a named option and all of its values
from a section.

 $ini->delete_name( $section, $name );

To delete an option from the 'null section', pass just the name, or
pass a null string.

 $ini->delete_name( $name );
 $ini->delete_name( '', $name );

To delete just some of the values, you can use C<set()> with a
subscript, passing C<undef> to delete each one.  Or you can first get
them into an array using C<get()>, modify them in that array (e.g.,
delete some), and then use C<put()> to replace the old values with the
modified ones.

=back

=head2 Other Accessor Methods

=over 8

=item file( $value )

Use C<file()> to get or set the C<'file'> object attribute, which is
intended to be the filename of the Ini file from which the object was
created.

 $inifile = $ini->file();  # get the name of the file

If C<$value> is not given, C<file()> returns the value of the C<'file'>
attribute.  If C<$value> is defined, C<'file'> is set to C<$value>.  If
C<$value> is given but is C<undef>, the C<'file'> attribute is
removed.

 $ini->file();                # return the file name
 $ini->file( 'myfile.ini' );  # change the file name
 $ini->file( undef );         # remove the file attribute

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

Copyright (C) 2008 by Brad Baxter

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.7 or,
at your option, any later version of Perl 5 you may have available.

=cut
