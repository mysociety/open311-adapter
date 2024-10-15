package Open311::Endpoint::Service::UKCouncil::Symology::Bexley;

use Moo;
extends 'Open311::Endpoint::Service::UKCouncil::Symology';
with 'Open311::Endpoint::Role::BexleyPrivateComments';

use Open311::Endpoint::Service::Attribute;

sub _build_attributes {
    my $self = shift;

    my @attributes = (
        @{ $self->SUPER::_build_attributes() },

        $self->private_comments_attribute,
    );

    return \@attributes;
}

1;
