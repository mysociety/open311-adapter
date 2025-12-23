package Open311::Endpoint::Integration::UK::Enfield;

use Moo;
extends 'Open311::Endpoint::Integration::Verint';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'enfield_verint';
    return $class->$orig(%args);
};

1;
