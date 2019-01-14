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

    my $source_types = $self->alloy->get_source_types();
    my @services = ();
    for my $source_type (@$source_types) {
        my %service = (
            description => $source_type->{description},
            service_name => $source_type->{description},
            service_code => $source_type->{sourceTypeId},
        );
        push @services, $self->service_class->new(%service);
    }
    return @services;
}

1;
