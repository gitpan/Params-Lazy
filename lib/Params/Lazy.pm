package Params::Lazy;

{ require 5.008 };
use strict;
use warnings FATAL => 'all';

use Carp;

# The call checker API is available on newer Perls;
# making the dependency on D::CC conditional lets me
# test this on an uninstalled blead.
use if $] < 5.014, "Devel::CallChecker";

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT    = "force";
our @EXPORT_OK = "force";

our $VERSION = '0.001';

require XSLoader;
XSLoader::load('Params::Lazy', $VERSION);

sub import {
    my $self = shift;
    
    if ( @_ && @_ % 2 ) {
        croak("You passed in an uneven list of values, "
            . "but that doesn't make sense");
    }
    
    while (@_) {
        my ($name, $proto) = splice(@_, 0, 2);
        if (grep !defined, $name, $proto) {
           croak("Both the function name and the "
               . "pseudo-prototype must be defined");
        }

        my $coderef;
        if ( (ref($name) || "") eq 'CODE' ) {
            $coderef = $name;
        }
        else {
            if ($name !~ /::/) {
               $name = scalar caller() . "::" . $name;
            }
 
            $coderef = do { no strict "refs"; *{$name}{CODE} };
 
            if ( !$coderef ) {
                croak("$name should already be defined or "
                    . "predeclared before trying to give it "
                    . "lazy magic");
            }
        }
        
        Params::Lazy::cv_set_call_checker_delay($coderef, $proto);
    }

    $self->export_to_level(1);
}

1;

=encoding utf8

=head1 NAME

Params::Lazy - Transparent lazy arguments for subroutines.

=head1 VERSION

Version 0.001

=head1 SYNOPSIS

    sub delay {
        say "One";
        force($_[0]);
        say "Three";
    }
    use Params::Lazy delay => '^';

    delay say "Two"; # Will output One, Two, Three

    sub fakemap {
       my $delayed = shift;
       my @retvals;
       push @retvals, force($delayed) for @_;
       return @retvals;
    }
    use Params::Lazy fakemap => '^@';

    my @goodies = fakemap "<$_>", 1..10; # same as map "<$_>", 1..10;
    ...
    
    sub fakegrep (&@) {
        my $delayed = shift;
        my $coderef = ref($delayed) eq 'CODE';
        my @retvals;
        for (@_) {
            if ($coderef ? $delayed->() : force($delayed)) {
                push @retvals, $_;
            }
        }
        return @retvals;
    }
    use Params::Lazy fakegrep => ':@';
    
    say fakegrep { $_ % 2 } 9, 16, 25, 36;
    say fakegrep   $_ % 2,  9, 16, 25, 36;

=head1 DESCRIPTION

The Params::Lazy module provides a way to transparently create lazy
arguments for a function, without the callers being aware that anything
unusual is happening under the hood.

You can enable a lazy argument by defining a function normally, then
C<use> the module, followed by the function name, and a 
prototype-looking string.  Besides the normal characters allowed in a
prototype, that string takes two new options: A caret (C<^>) which means
"make this argument lazy", and a colon (C<:>), which will be explained
later.
After that, when the function is called, instead of receiving the
result of whatever expression the caller put there, the delayed
arguments will instead be a simple scalar reference.  Only if you
pass that variable to C<force()> will the delayed expression be run.

The colon (C<:>) is special cased to work with the C<&> prototype. 
The gist of it is that, if the expression is something that the
C<&> prototype would allow, it stays out of the way and gives you that.
Otherwise, it gives you a delayed argument you can use with C<force()>.

=head1 EXPORT

=head2 force($delayed)

Runs the delayed code.

=head1 LIMITATIONS

=over

=item *

When using the C<:> prototype, these two cases are indistinguishable:

    myfunction { ... }
    myfunction sub { ... }

Which means that C<mymap sub { ... }, 1..10> will work
differently than the default map.

=item *

Strange things will happen if you goto LABEL out of a lazy argument.

=item *

It's also important to note that delayed arguments are *not* closures,
so storing them for later use will likely lead to crashes, segfaults,
and a general feeling of malignancy to descend upon you, your family,
and your cat.  Passing them to other functions should work fine, but
returning them to the place where they were delayed is generally a
bad idea.

=item *

Throwing an exception within a delayed eval might not work
properly on older Perls (particularly, the 5.8 series).
Similarly, there's a bug in Perls 5.10.1 through 5.12.5
that makes delaying a regular expression likely to crash
the program.

=item *

Finally, delayed arguments, although intended to be faster & more light
weight than coderefs, are currently about twice as slow as passing
a coderef and dereferencing it, so beware!

=back

=head1 AUTHOR, LICENSE AND COPYRIGHT

Copyright 2013 Brian Fraser, C<< <fraserbn at gmail.com> >>

This program is free software; you may redistribute it and/or modify it under the same terms as perl.

=head1 ACKNOWLEDGEMENTS

To Scala for the inspiration, to #p5p in general for holding my hand as I
stumbled through the callchecker, and to Zefram for L<Devel::CallChecker>
and spotting a leak.

=cut

1; # End of Params::Lazy
