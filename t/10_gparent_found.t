use Test::More;

package Base;

use Class::Accessor::Inherited::XS {
    inherited => [qw/foo/],
};

@Child1::ISA = qw/Base/;
@Child2::ISA = qw/Child1/;
@Child3::ISA = qw/Child2/;
@Child4::ISA = qw/Child3/;

package main;

is(Child3->foo, undef);

#exercise 'reset_stash_cache' behaviour w.r.t adding new junctions

is(Base->foo(42), 42);
is(Child2->foo, 42);
is(Child3->foo, 42);

is(Child2->foo(17), 17);
is(Child3->foo, 17);
is(Child1->foo, 42);

is(Base->foo(11), 11);
is(Child1->foo, 11);
is(Child2->foo, 17);
is(Child3->foo, 17);

is(Child2->foo(23), 23);
is(Child1->foo, 11);
is(Child3->foo, 23);

is(Child4->foo, 23);
is(Child3->foo(77), 77);
is(Child4->foo, 77);
is(Child2->foo, 23);

# exercise 'reset_stash_cache' behaviour w.r.t clearing values

is(Child3->foo(undef), undef);
is(Child4->foo, 23);
is(Child3->foo, 23);

is(Child4->foo(80), 80);
is(Child3->foo, 23);
is(Child4->foo, 80);
is(Child4->foo(undef), undef);
is(Child4->foo, 23);

is(Child3->foo(100), 100);
is(Child4->foo, 100);
is(Child3->foo, 100);

is(Child3->foo(undef), undef);
is(Child2->foo(undef), undef);
is(Base->foo(undef), undef);

is(Child4->foo, undef);
is(Base->foo, undef);

is(Child4->foo(113), 113);
is(Child3->foo, undef);

is(Child2->foo(140), 140);
is(Child3->foo, 140);
is(Child1->foo, undef);

is(Base->foo(150), 150);
is(Child1->foo, 150);
is(Child2->foo, 140);
is(Child3->foo, 140);
is(Child4->foo, 113);

is(Base->foo(undef), undef);
is(Child1->foo, undef);
is(Child2->foo(undef), undef);
is(Child3->foo, undef);

is(Base->foo(200), 200);
is(Child3->foo, 200);

done_testing;
