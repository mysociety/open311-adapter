package Open311::Endpoint::Service::UKCouncil::Alloy::Bristol;
use Moo;
extends 'Open311::Endpoint::Service::UKCouncil::Alloy';

use Open311::Endpoint::Service::Attribute;

sub _build_attributes {
    my $self = shift;

    my @attributes = (
        @{ $self->SUPER::_build_attributes() },
        Open311::Endpoint::Service::Attribute->new(
            code => "usrn",
            description => "USRN",
            datatype => "string",
            required => 1,
            automated => 'hidden_field',
        ),
    );

    return \@attributes;
}

1;

