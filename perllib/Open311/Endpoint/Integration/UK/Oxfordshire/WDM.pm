package Open311::Endpoint::Integration::UK::Oxfordshire::WDM;

use Moo;
extends 'Open311::Endpoint::Integration::WDM';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'oxfordshire_wdm';
    return $class->$orig(%args);
};

1;
