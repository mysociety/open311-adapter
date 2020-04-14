package Open311::Endpoint::Integration::SalesForceRest;

use Moo;
extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';

use Open311::Endpoint::Service::Attribute;
use Open311::Endpoint::Service::UKCouncil::Salesforce;

use Integrations::SalesForceRest;

use DateTime::Format::Strptime;
use Types::Standard ':all';

sub service_request_content {
    '/open311/service_request_extended'
}

has jurisdiction_id => ( is => 'ro' );

has '+identifier_types' => (
    is => 'lazy',
    isa => HashRef[Any],
    default => sub {
        my $self = shift;
        return {
            # type names can have all sorts in them
            service_code => { type => '/open311/regex', pattern => qr/^ [\w_\- \/\(\),&;]+ $/ax },
        };
    },
);

has blacklist => (
    is => 'lazy',
    default => sub {
        my $self = shift;
        my %blacklist = map { $_ => 1 } @{ $self->get_integration->config->{service_blacklist} };
        return \%blacklist;
    }
);

has whitelist => (
    is => 'lazy',
    default => sub {
        my $self = shift;
        my %whitelist = map { $_ => 1 } @{ $self->get_integration->config->{service_whitelist} };
        return \%whitelist;
    }
);

sub integration_class { 'Integrations::SalesForceRest' }

sub get_integration {
    my $self = shift;
    return $self->integration_class->new(config_filename => $self->jurisdiction_id);
}

sub post_service_request {
    my ($self, $service, $args) = @_;
    die "No such service" unless $service;

    my $defaults = $self->get_integration->config->{field_defaults};
    my $mapping = $self->get_integration->config->{field_map};
    my $map = { map { $mapping->{$_} => $args->{$_} } keys %$mapping };

    my $req = {
        %$defaults,
        %$map
    };

    my $user_id = $self->_get_user($args);

    die "Failed to get user id" unless $user_id;

    $req->{ $mapping->{title} } = $args->{attributes}->{group} || $service->groups->[0];
    $req->{ $mapping->{group} } = $args->{attributes}->{group} || $service->groups->[0];
    $req->{ $mapping->{account} } = $user_id;

    # most categories use a type and a sub type which map to
    # group and service code. Some though just have a type in
    # which case group and service code are the same so delete
    # the service code and only send the group.
    if ( scalar( @{ $service->{groups} } ) == 1
         && $service->groups->[0] eq $service->service_code ) {
        delete $req->{ $mapping->{service_code} };
    }

    my $new_id = $self->get_integration->post_request($service, $req);

    my $request = $self->new_request(
        service_request_id => $new_id,
    );

    return $request;
}

sub services {
    my ($self, $args) = @_;

    my @services = $self->get_integration->get_services($args);

    my @service_types;
    for my $service ( @services ) {
        next unless scalar @{ $service->{groups} };

        next unless grep { $self->whitelist->{$_} } @{ $service->{groups} };

        next if $self->blacklist->{$service->{value}};

        my $service = Open311::Endpoint::Service::UKCouncil::Salesforce->new(
            service_name => $service->{label},
            description => $service->{label},
            service_code => $service->{value},
            groups => $service->{groups},
        );

        push @service_types, $service;
    }

    return @service_types;
}

sub service {
    my ($self, $id, $args) = @_;

    my $meta = $self->get_integration->get_service($id, $args);

    my $service = Open311::Endpoint::Service::UKCouncil::Salesforce->new(
        service_name => $meta->{label},
        description => $meta->{label},
        service_code => $meta->{value},
        groups => $meta->{groups},
    );

    my $map = $self->get_integration->config->{extra_questions}->{category_map};
    my $question_map = { map { my $k = $_; map { $_ => $k } @{ $map->{$k} } } keys %$map };

    if ( $question_map->{$id} ) {
        my $questions =  $self->get_integration->config->{extra_questions}->{questions}->{$question_map->{$id}};
        for my $q ( @$questions ) {
            next unless $q->{question};
            (my $code = $q->{question}) =~ s/ /_/g;
            $code =~ s/[^a-zA-Z_]//g;
            my $attribs = {
                code => lc $code,
                description => $q->{question},
                required => 0,
                datatype => 'string',
            };
            if ($q->{answers}) {
                $attribs->{datatype} = 'singlevaluelist';
                $attribs->{values} = { map { ref $_ eq 'ARRAY' ? ( $_->[0] => $_->[1] ) : ( $_ => $_ ) } @{ $q->{answers} } };
            }

            push @{ $service->attributes }, Open311::Endpoint::Service::Attribute->new($attribs);
        }
    }

    return $service;
}

sub _get_user {
    my ($self, $args) = @_;

    my $id;

    my $results = $self->get_integration->find_user( $args->{email} );

    if ($results->{searchRecords}->[0]) {
        $id = $results->{searchRecords}->[0]->{Id};
    } else {
        # create record here
        my $defaults = $self->get_integration->config->{account_defaults};
        my $mapping = $self->get_integration->config->{account_map};
        my $map = { map { $mapping->{$_} => $args->{$_} } keys %$mapping };

        my $account = {
            %$defaults,
            %$map
        };

        $id = $self->get_integration->post_user( $account );
    }

    return $id;
}

__PACKAGE__->run_if_script;
