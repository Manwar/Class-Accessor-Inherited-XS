use Test::More;

sub exception (&) {
    $@ = undef;
    eval { shift->() };
    $@
}

package Test;

use Class::Accessor::Inherited::XS {
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

like exception {TestC->foo}, qr/locate object method "foo"/;

done_testing;
