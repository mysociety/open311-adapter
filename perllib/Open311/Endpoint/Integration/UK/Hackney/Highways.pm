package Open311::Endpoint::Integration::UK::Hackney::Highways;

use Moo;
extends 'Open311::Endpoint::Integration::UK::Hackney::Base';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'hackney_highways_alloy_v2';
    return $class->$orig(%args);
};

1;
