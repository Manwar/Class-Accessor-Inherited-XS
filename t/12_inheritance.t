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

@Test::D::ISA = qw/Test::A/;
is(Test::D->foo, 12);

Test->foo(undef);
@Test::C::ISA = qw/Test/;
@Test::A::ISA = qw/Test::C/;

is(Test::C->foo(42), 42);
is(Test::A->foo, 42);

Test->foo(70);
@Test::E::ISA = qw/Test::B/;
is(Test::E->foo, 70);

done_testing;