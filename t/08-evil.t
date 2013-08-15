use strict;
use warnings;

use Test::More;

sub lazy_run {
    FOO: {
        eval { force($_[0]) };
        like($@, $_[1], $_[2]);
        return;
    }
    fail("Should not get here");
}
use Params::Lazy lazy_run => '^$;$';

sub empty {}

lazy_run return, qr/\QCan't return outside a subroutine/, "a delayed return dies";
FOO: { lazy_run last FOO, qr/\QLabel not found for "last FOO"/, "a delayed last dies" };
FOO: { lazy_run goto FOO, qr/\QCan't find label FOO/, "a delayed goto LABEL dies" };
lazy_run goto &empty, qr/\QCan't goto subroutine outside a subroutine/, "a delayed goto &sub dies"; #'

sub modify_params_list {
    my ($delay) = @_;
    is(force($delay), $delay);
    return @_;
}
use Params::Lazy modify_params_list => '^;@';

my @ret = modify_params_list(shift(@_), 1..10);
is_deeply(\@ret, [1..10], "can modify \@_ from a lazy arg");

sub run_evil { force($_[0]); fail("Should never reach here") }
use Params::Lazy run_evil => '^';

my $pid = open my $pipe, '-|';

if (defined $pid) {    
    if ( $pid ) {
        my @out = <$pipe>;
        waitpid $pid, 0;
        my $exit_status = $? >> 8;
        is($exit_status, 150, "lazy_run exit()");
        is(join("", @out), "", "..doesn't produce unexpected output");
    }
    else {
        open(STDERR, ">&", STDOUT);
        run_evil exit(150);
        die "Should never reach here";
    }
}

=begin goto, Pathological

no warnings 'deprecated';
run_evil do { goto DOO; };
NOPE: {
    last NOPE;
    DOO:
    {
        pass("goto works"); # Whenever it should...
    }
}
=cut

done_testing;
