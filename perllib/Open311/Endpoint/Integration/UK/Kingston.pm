package Open311::Endpoint::Integration::UK::Kingston;

use Moo;
extends 'Open311::Endpoint::Integration::Echo';
with 'Open311::Endpoint::Role::SLWP';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'kingston_echo';
    return $class->$orig(%args);
};

has cancel_actiontype_id => ( is => 'ro', default => 8 );

1;
