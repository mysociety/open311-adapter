package Open311::Endpoint::Service::UKCouncil::Boomi;
use Moo;
extends 'Open311::Endpoint::Service::UKCouncil';

use Open311::Endpoint::Service::Attribute;

sub _build_attributes {
    my $self = shift;

    my @attributes = (
        @{ $self->SUPER::_build_attributes() },
        Open311::Endpoint::Service::Attribute->new(
            code => "report_url",
            description => "Report URL",
            datatype => "string",
            required => 1,
            automated => 'server_set',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => "title",
            description => "Title",
            datatype => "string",
            required => 1,
            automated => 'server_set',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => "description",
            description => "Description",
            datatype => "text",
            required => 1,
            automated => 'server_set',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => "group",
            description => "Group",
            datatype => "string",
            required => 0,
            automated => 'server_set',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => "category",
            description => "Category",
            datatype => "string",
            required => 1,
            automated => 'server_set',
        ),

        # XXX these should not be hardcoded here but haven't yet figured out
        # how to allow any attribute/value to pass schema validation
        Open311::Endpoint::Service::Attribute->new(
            code => "Q7",
            description => "Q7",
            datatype => "multivaluelist",
            required => 0,
            variable => 1,
            allow_any_value => 1,
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => "pothole_severity",
            description => "pothole_severity",
            datatype => "multivaluelist",
            required => 0,
            variable => 1,
            allow_any_value => 1,
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => "pothole_location",
            description => "pothole_location",
            datatype => "multivaluelist",
            required => 0,
            variable => 1,
            allow_any_value => 1,
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => "D1_Declaration",
            description => "D1_Declaration",
            datatype => "multivaluelist",
            required => 0,
            variable => 1,
            allow_any_value => 1,
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => "1_Location",
            description => "1_Location",
            datatype => "multivaluelist",
            required => 0,
            variable => 1,
            allow_any_value => 1,
        ),
    );

    return \@attributes;
}

1;
