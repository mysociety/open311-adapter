package Open311::Endpoint::Integration::UK::Brent::ATAK;

use Moo;
extends 'Open311::Endpoint::Integration::ATAK';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'brent_atak';
    return $class->$orig(%args);
};

1;
