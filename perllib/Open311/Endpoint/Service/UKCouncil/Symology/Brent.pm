package Open311::Endpoint::Service::UKCouncil::Symology::Brent;

use Moo;
extends 'Open311::Endpoint::Service::UKCouncil::Symology';

use Open311::Endpoint::Service::Attribute;

sub _build_attributes {
    my $self = shift;

    my @attributes = (
        @{ $self->SUPER::_build_attributes() },

        Open311::Endpoint::Service::Attribute->new(
            code => "title",
            description => "Title",
            datatype => "string",
            required => 0,
            automated => 'server_set',
        ),
    );

    return \@attributes;
}

1;
