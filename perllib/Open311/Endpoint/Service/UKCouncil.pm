package Open311::Endpoint::Service::UKCouncil;
use Moo;
extends 'Open311::Endpoint::Service';
use Open311::Endpoint::Service::Attribute;

sub _build_attributes {
    return [
        Open311::Endpoint::Service::Attribute->new(
            code => 'easting',
            variable => 0, # set by server
            datatype => 'number',
            required => 1,
            automated => 'server_set',
            description => 'easting',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => 'northing',
            variable => 0, # set by server
            datatype => 'number',
            required => 1,
            automated => 'server_set',
            description => 'northing',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => 'fixmystreet_id',
            variable => 0, # set by server
            datatype => 'string',
            required => 1,
            automated => 'server_set',
            description => 'external system ID',
        ),
    ];
}

1;
