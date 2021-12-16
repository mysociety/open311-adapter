package Open311::Endpoint::Integration::SalesForce::EastSussex;

use Moo;
extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';

use Open311::Endpoint::Service::Attribute;
use Open311::Endpoint::Service::UKCouncil::Salesforce;

use Integrations::SalesForce::EastSussex;

use DateTime::Format::Strptime;
use Types::Standard ':all';
use Try::Tiny;

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

has group_service_blacklist => (
    is => 'lazy',
    default => sub {
        my $self = shift;
        my %blacklist;
        my $blacklist = $self->get_integration->config->{group_service_blacklist};
        for my $group ( keys %$blacklist ) {
            $blacklist{$group} = { map { $_ => 1 } @{ $blacklist->{$group} } };
        }
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

sub integration_class { 'Integrations::SalesForce::EastSussex' }

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

    my $user = $self->_get_user($args);

    die "Failed to get user id" unless $user;

    my $group = $self->_revert_group_name( $args->{attributes}->{group} || $service->groups->[0] );

    $req->{ $mapping->{title} } = $group;
    $req->{ $mapping->{group} } = $group;
    $req->{ $mapping->{account} } = $user->{id};
    $req->{ $mapping->{contact} } = $user->{contact_id};

    if ( $args->{attributes}->{asset_id} ) {
        $req->{ $mapping->{asset} } = $args->{attributes}->{asset_id};
    } else {
        delete $req->{ $mapping->{asset} };
    }

    $self->_add_closest_address($req, $args, $mapping);

    # most categories use a type and a sub type which map to
    # group and service code. Some though just have a type in
    # which case group and service code are the same so delete
    # the service code and only send the group.
    if ( scalar( @{ $service->{groups} } ) == 1
         && $service->groups->[0] eq $service->service_code ) {
        delete $req->{ $mapping->{service_code} };
    }

    my $new_id = $self->get_integration->post_request($service, $req);

    if ( $args->{media_url} ) {
        try {
            my $photo_id = $self->_add_attachment( $new_id, $args->{media_url} );
        } catch {
            $self->logger->warn("failed to upload photo for report $new_id: $_");
        }
    }

    my $case = $self->get_integration->get_case($new_id);

    my $request = $self->new_request(
        service_request_id => $case->{CaseNumber},
    );

    return $request;
}

sub services {
    my ($self, $args) = @_;

    my @services = $self->get_integration->get_services($args);

    my @service_types;
    for my $service ( @services ) {
        # remove any groups that are blacklisted for this service in
        # cases where one service name is in multiple groups
        $service->{groups} = [ grep { !$self->group_service_blacklist->{ $_ }->{ $service->{label} } } @{ $service->{groups} } ];

        next unless scalar @{ $service->{groups} };

        my @groups = grep { $self->whitelist->{$_} } @{ $service->{groups} };
        next unless @groups;


        next if $self->blacklist->{$service->{value}};

        my $service = Open311::Endpoint::Service::UKCouncil::Salesforce->new(
            service_name => $service->{label},
            description => $service->{label},
            service_code => $service->{value},
            groups => $self->_rename_groups( \@groups ),
        );

        push @service_types, $service;
    }

    return @service_types;
}

sub service {
    my ($self, $id, $args) = @_;

    my $meta = $self->get_integration->get_service($id, $args);
    my @groups = grep { $self->whitelist->{$_} } @{ $meta->{groups} };

    my $service = Open311::Endpoint::Service::UKCouncil::Salesforce->new(
        service_name => $meta->{label},
        description => $meta->{label},
        service_code => $meta->{value},
        groups => $self->_rename_groups( \@groups ),
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
                $attribs->{values_sorted} = [ map {  ref $_ eq 'ARRAY' ? $_->[0] : $_ } @{ $q->{answers} } ] if $q->{maintain_order};
            }

            push @{ $service->attributes }, Open311::Endpoint::Service::Attribute->new($attribs);
        }
    }

    return $service;
}

# next two functions are to enable us to user more user friendly names on
# FixMyStreet. They map a Type name to a user friendly name for services
# and then enable that to be reversed when creating a Case.
# This does rely on us not renaming two groups to the same thing.
sub _rename_groups {
    my ($self, $groups) = @_;

    my $map = $self->get_integration->config->{group_name_map};

    return $groups unless $map;

    $groups = [
        map {
            $map->{$_} || $_
        } @{ $groups }
    ];

    return $groups;
}

sub _revert_group_name {
    my ($self, $group) = @_;

    my $map = $self->get_integration->config->{group_name_map};

    return $group unless $map;

    my %reverse_map = reverse %$map;

    return $reverse_map{$group} || $group;
}

sub _get_user {
    my ($self, $args) = @_;

    my $results = $self->get_integration->find_user( $args->{email} );

    my $obj = {};
    if ($results->{searchRecords}->[0]) {
        $obj = {
            id => $results->{searchRecords}->[0]->{Id},
            contact_id => $results->{searchRecords}->[0]->{PersonContactId},
        };
    } else {
        # create record here
        my $defaults = $self->get_integration->config->{account_defaults};
        my $mapping = $self->get_integration->config->{account_map};
        my $map = { map { $mapping->{$_} => $args->{$_} } keys %$mapping };

        my $args = {
            %$defaults,
            %$map
        };

        my $account = $self->get_integration->post_user( $args );

        $obj = {
            id => $account->{Id},
            contact_id => $account->{PersonContactId},
        };
    }

    return $obj;
}

sub _add_closest_address {
    my ($self, $req, $args, $mapping) = @_;

    my ($address) = $args->{attributes}->{closest_address} =~ /Nearest[^:]*: (.+)$/m;

    $req->{ $mapping->{address_string} } = $address
}

sub _add_attachment {
    my ($self, $id, $media_urls) = @_;

    # Grab each photo from FMS
    my $ua = LWP::UserAgent->new(agent => "FixMyStreet/open311-adapter");
    my @photos = map {
        $ua->get($_);
    } @$media_urls;

    # upload the file to the folder, with a FMS-related name
    my @resource_ids = map {
        $self->get_integration->post_attachment($id, $_);
    } @photos;

    return \@resource_ids;
}

__PACKAGE__->run_if_script;
