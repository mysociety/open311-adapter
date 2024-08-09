package Open311::Endpoint::Integration::UK::Surrey;

use Moo;
extends 'Open311::Endpoint::Integration::Boomi';

around BUILDARGS => sub {
    my ( $orig, $class, %args ) = @_;
    $args{jurisdiction_id} = 'surrey_boomi';
    return $class->$orig(%args);
};

1;
