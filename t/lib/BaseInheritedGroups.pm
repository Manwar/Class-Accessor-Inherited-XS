package BaseInheritedGroups;
use strict;
use warnings;
use base 'AccessorInstaller';

if (!$::DO_OPTIMIZE) {
    __PACKAGE__->mk_inherited_accessors('basefield', 'undefined', ['refacc','reffield']);
} else {
    __PACKAGE__->mk_inherited_accessors(['basefield', 'basefield', 1]);
    __PACKAGE__->mk_inherited_accessors(['undefined', 'undefined', 1]);
    __PACKAGE__->mk_inherited_accessors(['refacc',    'reffield',  1]);
}

sub new {
    return bless {}, shift;
};

1;
