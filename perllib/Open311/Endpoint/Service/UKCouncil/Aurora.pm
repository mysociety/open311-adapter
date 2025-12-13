package Open311::Endpoint::Service::UKCouncil::Aurora;
use Moo;
extends 'Open311::Endpoint::Service::UKCouncil';

use Open311::Endpoint::Service::Attribute;

sub _build_attributes {
    my $self = shift;

    my @attributes = (
        @{ $self->SUPER::_build_attributes() },

        Open311::Endpoint::Service::Attribute->new(
            code => "UnitID",
            description => "Unit ID",
            datatype => "string",
            required => 0,
            automated => 'hidden_field',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => "NSGRef",
            description => "NSG reference",
            datatype => "string",
            required => 0,
            automated => 'hidden_field',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => "contributed_by",
            description => "Contributed by",
            datatype => "string",
            required => 0,
            automated => 'server_set',
        ),
        Open311::Endpoint::Service::Attribute->new(
            code => "area_code",
            description => "Area code",
            datatype => "string",
            required => 0,
            automated => 'server_set',
        ),
    );

    return \@attributes;
}

1;
