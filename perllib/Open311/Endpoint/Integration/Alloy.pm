package Open311::Endpoint::Integration::Alloy;

use Moo;
use List::Util 'first';
use DateTime::Format::W3CDTF;
extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Open311::Endpoint::Role::ConfigFile';

use Open311::Endpoint::Service::UKCouncil::Alloy;
use Open311::Endpoint::Service::Attribute;
use Open311::Endpoint::Service::Request::CanBeNonPublic;

use Path::Tiny;

use Data::Dumper;


around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    die unless $args{jurisdiction_id}; # Must have one by here
    $args{config_file} //= path(__FILE__)->parent(5)->realpath->child("conf/council-$args{jurisdiction_id}.yml")->stringify;
    return $class->$orig(%args);
};

has jurisdiction_id => (
    is => 'ro',
);

has '+request_class' => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::Request::CanBeNonPublic',
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
            service_code => $self->service_code_for_source($source),
        );
        my $o311_service = $self->service_class->new(%service);
        for my $attrib (@{$source->{attributes}}) {
            my %overrides = ();
            if (defined $self->config->{attribute_overrides}->{$attrib->{name}}) {
                %overrides = %{ $self->config->{attribute_overrides}->{$attrib->{name}} };
            }

            push @{$o311_service->attributes}, Open311::Endpoint::Service::Attribute->new(
                code => $attrib->{id},
                description => $attrib->{description},
                datatype => $attrib->{datatype},
                required => $attrib->{required},
                values => $attrib->{values},
                %overrides,
            );
        }
        push @services, $o311_service;
    }
    return @services;
}

sub post_service_request {
    my ($self, $service, $args) = @_;
    die "No such service" unless $service;

    # Get the service code from the args/whatever
    # get the appropriate source type
    my $sources = $self->alloy->get_sources();
    my $source = first { $self->service_code_for_source($_) eq $service->service_code } @$sources;

    printf STDERR Dumper($args);
    printf STDERR Dumper($source);

    # extract attribute values
    my $resource_id = $args->{attributes}->{asset_resource_id} + 0;
    my $resource = {
        networkReference => undef,
        sourceId => $source->{source_id},
        parents => {
            "$source->{parent_attribute_id}" => [ $resource_id ],
        },
        geoJson => {
            type => "Point",
            coordinates => [
                $args->{long},
                $args->{lat}
            ],
        }
    };
    foreach (qw/report_url fixmystreet_id northing easting asset_resource_id title description/) {
        delete $args->{attributes}->{$_};
    }
    $resource->{attributes} = $args->{attributes};


    # figure out the default values for attributes which
    # FMS hasn't sent
    # some will be hardcoded defaults (source etc)
    # others computed (easting, northing, category, reported datetime etc)

    # upload any photos and get their resource IDs, set attachment attribute IDs (?)

    # generate the geometry

    # set the parent attribute value to the resource ID

    # post it up
    my $response = $self->alloy->api_call("resource", undef, $resource);

    # get the Alloy inspection reference
    my $alloy_ref = $response->{resourceId};

    # create a new Request and return it
    return $self->new_request(
        service_request_id => $alloy_ref
    );

}

sub service_code_for_source {
    my ($self, $source) = @_;

    return $source->{source_id} . "_" . $source->{parent_attribute_id};
}

1;
