use Test::More;
use strict;
use warnings;
use lib 't/lib';
use SuperInheritedGroups;

my $simple = SuperInheritedGroups->new;
$simple->basefield('Yess');
is($simple->basefield, 'Yess', 'Simple set obj, get obj');
$simple->basefield('Yess2');
is($simple->basefield, 'Yess2', 'Simple set obj, get obj');

$simple->refacc('refacc');
is($simple->refacc, 'refacc', 'Simple set/get for form [acc,field]');
is($simple->{reffield}, 'refacc', 'Ensure right field name for form [acc,field]');

my $super = SuperInheritedGroups->new;
my $base = BaseInheritedGroups->new;

my @ret = SuperInheritedGroups->basefield;

ok(@ret == 1, 'Return value before set');
ok(!defined(SuperInheritedGroups->basefield), 'Undef return before set');

# set base. base, super, object = base
is(BaseInheritedGroups->basefield('QQQ'), 'QQQ');
is(SuperInheritedGroups->basefield, 'QQQ');
is($super->basefield, 'QQQ');
is($base->basefield, 'QQQ');

# set base. base, super, object = base to another value
is(BaseInheritedGroups->basefield('All Your Base'), 'All Your Base');
is(SuperInheritedGroups->basefield, 'All Your Base');
is($super->basefield, 'All Your Base');
is($base->basefield, 'All Your Base');

# set super. super = super, base = base, object = super
is(SuperInheritedGroups->basefield('Now Its Our Base'), 'Now Its Our Base');
is(SuperInheritedGroups->basefield, 'Now Its Our Base');
is(BaseInheritedGroups->basefield, 'All Your Base');
is($super->basefield, 'Now Its Our Base');
is($base->basefield, 'All Your Base');

#set base
is($base->basefield('First Base'), 'First Base');
is($base->basefield, 'First Base');
is($super->basefield, 'Now Its Our Base');
is(BaseInheritedGroups->basefield, 'All Your Base');
is(SuperInheritedGroups->basefield, 'Now Its Our Base');

# set object, object = object, super = super, base = base
is($super->basefield('Third Base'), 'Third Base');
is($super->basefield, 'Third Base');
is(SuperInheritedGroups->basefield, 'Now Its Our Base');
is(BaseInheritedGroups->basefield, 'All Your Base');

# create new super. new = base, object = object, super = super, base = base
my $newsuper = SuperInheritedGroups->new;
is($newsuper->basefield, 'Now Its Our Base');
is($super->basefield, 'Third Base');
is(SuperInheritedGroups->basefield, 'Now Its Our Base');
is(BaseInheritedGroups->basefield, 'All Your Base');

# create new base. new = base, super = super, base = base
my $newbase = BaseInheritedGroups->new;
is($newbase->basefield, 'All Your Base');
is($newsuper->basefield, 'Now Its Our Base');
is($super->basefield, 'Third Base');
is(SuperInheritedGroups->basefield, 'Now Its Our Base');
is(BaseInheritedGroups->basefield, 'All Your Base');

# make sure we're get defined items, even 0, ''
BaseInheritedGroups->basefield('base');
SuperInheritedGroups->basefield(0);
is(SuperInheritedGroups->basefield, 0);

BaseInheritedGroups->basefield('base');
SuperInheritedGroups->basefield('');
is(SuperInheritedGroups->basefield, '');

BaseInheritedGroups->basefield('base');
SuperInheritedGroups->basefield(undef);
is(SuperInheritedGroups->basefield, 'base');

is(BaseInheritedGroups->undefined, undef);

# make sure run-time @ISA changes trigger an inheritance chain recalculation
SuperInheritedGroups->basefield(undef);
BaseInheritedGroups->basefield('your base');

# dirty hack, emulate Class::C3::Componentised
require ExtraInheritedGroups;
unshift @SuperInheritedGroups::ISA, qw/ExtraInheritedGroups/;

# this comes from ExtraInheritedGroups
is(SuperInheritedGroups->basefield, 'your extra base!');

done_testing;
