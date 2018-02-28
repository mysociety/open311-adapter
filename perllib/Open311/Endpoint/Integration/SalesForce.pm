package Open311::Endpoint::Integration::SalesForce;

use Moo;
extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';

use Open311::Endpoint::Service::UKCouncil::Rutland;
use Open311::Endpoint::Service::Attribute;
use Open311::Endpoint::Service::Request::Update::mySociety;

use Integrations::SalesForce;

use Digest::MD5 qw(md5_hex);
use DateTime::Format::Strptime;

sub reverse_status_mapping {}

sub get_integration {
    my $self = shift;
    return $self->integration_class->new;
}

sub post_service_request {
    my ($self, $service, $args) = @_;
    die "No such service" unless $service;

    my $integ = $self->get_integration;

    my $new_id = $integ->post_request($service, $args);

    my $request = $self->new_request(
        service_request_id => $new_id,
    );

    return $request;
}

sub services {
    my ($self, $args) = @_;

    my @services = $self->get_integration->get_services($args);

    my @service_types;
    for my $service (@services) {
        my $type = Open311::Endpoint::Service::UKCouncil::Rutland->new(
            service_name => $service->{name},
            service_code => $service->{serviceid},
            description => $service->{name},
            type => 'realtime',
            keywords => [qw/ /],
        );

        push @service_types, $type;
    }

    return @service_types;
}

sub service {
    my ($self, $id, $args) = @_;

    my $meta = $self->get_integration->get_service($id, $args);

    my $service = Open311::Endpoint::Service::UKCouncil::Rutland->new(
        service_name => $meta->{title},
        service_code => $id,
        description => $meta->{title},
        type => 'realtime',
        keywords => [qw/ /],
    );

    for my $meta (@{ $meta->{fieldInformation} }) {
        my %options = (
            code => $meta->{name},
            description => $meta->{label},
            required => 0,
        );
        if ($meta->{fieldType} eq 'text') {
            $options{datatype} = 'string';
        } else {
            my %values = map { $_ => $_ } @{ $meta->{optionsList} };
            $options{datatype} = 'singlevaluelist';
            $options{values} = \%values;
        }
        my $attrib = Open311::Endpoint::Service::Attribute->new(%options);
        push @{ $service->attributes }, $attrib;
    }

    return $service;
}

__PACKAGE__->run_if_script;
