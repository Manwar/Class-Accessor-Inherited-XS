use Test::More;

package Test;

use parent qw/Class::Accessor::Inherited::XS/;
__PACKAGE__->mk_inherited_accessor(qw/foo foo/);

@Test::A::ISA = qw/Test/;
@Test::B::ISA = qw/Test::A/;

package main;

is(Test::A->foo(12), 12);
is(Test::B->foo, 12);

@Test::B::ISA = qw/Test/;
is(Test::B->foo, undef);

@Test::E::ISA = qw/Test::D/;
@Test::D::ISA = qw/Test::A/;
is(Test::E->foo, 12);
is(Test::D->foo, 12);

Test->foo(undef);
@Test::C::ISA = qw/Test/;
@Test::A::ISA = qw/Test::C/;

is(Test::C->foo(42), 42);
is(Test::A->foo, 42);

Test->foo(70);
@Test::F::ISA = qw/Test::B/;
is(Test::F->foo, 70);

is(Test->foo(99), 99);
push @Test::ISA, 'NOP';
is(Test->foo, 99);

+undef @Test::F::ISA;
@Test::F::ISA = qw/Test::C/;
is(Test::F->foo, 42);

done_testing;
