package Open311::Endpoint::Integration::Alloy;

use Moo;
use DateTime::Format::W3CDTF;
extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Open311::Endpoint::Role::ConfigFile';

use Open311::Endpoint::Service::UKCouncil::Alloy;
use Open311::Endpoint::Service::Attribute;

use Path::Tiny;


around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    die unless $args{jurisdiction_id}; # Must have one by here
    $args{config_file} //= path(__FILE__)->parent(5)->realpath->child("conf/council-$args{jurisdiction_id}.yml")->stringify;
    return $class->$orig(%args);
};

has jurisdiction_id => (
    is => 'ro',
);

has alloy => (
    is => 'lazy',
    default => sub { $_[0]->integration_class->new }
);

=head2 service_class

Subclasses can override this to provide their own custom Service class, e.g.
if they want to have extra attributes on all services. We use the
UKCouncil::Alloy class which requests the asset's resource ID as a
separate attribute, so we can attach the defect to the appropriate asset
in Alloy.

=cut

has service_class  => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::UKCouncil::Alloy'
);


sub services {
    my $self = shift;

    my $sources = $self->alloy->get_sources();
    my @services = ();
    for my $source (@$sources) {

        my %service = (
            description => $source->{description},
            service_name => $source->{description},
            service_code => $source->{source_id} . "_" . $source->{parent_attribute_id},
        );
        my $o311_service = $self->service_class->new(%service);
        for my $attrib (@{$source->{attributes}}) {
            push @{$o311_service->attributes}, Open311::Endpoint::Service::Attribute->new(
                code => $attrib->{id},
                description => $attrib->{description},
                datatype => $attrib->{datatype},
                required => $attrib->{required},
                values => $attrib->{values},
            );
        }
        push @services, $o311_service;
    }
    return @services;
}

1;
