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
sub noreturn { 1 }
sub withreturn { return 1 }

my $cant_goto = qr/\QCan't goto subroutine \E(?:\Qfrom a sort sub (or similar callback)\E|outside a subroutine)/;  #'
lazy_run goto &empty, $cant_goto, "a delayed goto &emptysub dies";
lazy_run goto &noreturn, $cant_goto, "delayed goto &noexplicitreturn dies";
lazy_run goto &withreturn, $cant_goto, "delayed goto &explicitreturn dies";
    
sub {
    lazy_run goto &empty, $cant_goto, "inside a sub, a delayed goto &emptysub dies";
    lazy_run goto &noreturn, $cant_goto, "inside a sub, delayed goto &noexplicitreturn dies";
    lazy_run goto &withreturn, $cant_goto, "inside a sub, delayed goto &explicitreturn dies";
}->();

lazy_run return, qr/\QCan't return outside a subroutine/, "a delayed return dies";
FOO: { lazy_run last FOO, qr/\QLabel not found for "last FOO"/, "a delayed last dies" };
FOO: { lazy_run goto FOO, qr/\QCan't find label FOO/, "a delayed goto LABEL dies" };


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
