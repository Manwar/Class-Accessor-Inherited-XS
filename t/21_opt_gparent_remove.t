use Test::More;

sub exception (&) {
    $@ = undef;
    eval { shift->() };
    $@
}

package Test;

use Class::Accessor::Inherited::XS {
    optimize  => 1,
    inherited => [qw/foo/],
};

package TestC;
our @ISA=qw/Test/;

package Child;
our @ISA = qw/TestC/;

package main;

is(Test->foo(42), 42);
is(TestC->foo(12), 12);
is(Child->foo, 12);

@Child::ISA=qw/Test/;
@TestC::ISA=();

is(Child->foo, 42);
is(TestC->foo, 12); # preserved

is(Test->foo(77), 77);
is(TestC->foo, 12);

done_testing;
