package Open311::Endpoint::Integration::UK;

use Moo;
extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Open311::Endpoint::Role::CompletionPhotos';

use Types::Standard ':all';
use Module::Pluggable
    search_path => ['Open311::Endpoint::Integration::UK'],
    max_depth => 5,
    instantiate => 'new';
use JSON::MaybeXS;
use Path::Tiny;
use URI;

use Open311::Endpoint::Schema;

has '+jurisdiction_ids' => (
    default => sub { my $self = shift; [ map { $_->jurisdiction_id } $self->plugins ] },
);

# Make sure the jurisdiction_id is one of our IDs

has '+identifier_types' => (
    is => 'lazy',
    isa => HashRef[Any],
    default => sub {
        my $self = shift;
        my $ids = $self->jurisdiction_ids;
        return {} unless @$ids;
        return {
            jurisdiction_id => Open311::Endpoint::Schema->enum('//str', @$ids),
            # some service codes have spaces, ampersands, commas, etc
            service_code => { type => '/open311/regex', pattern => qr/^ [&,\.\w_\- \/\(\)]+ $/ax },
            # some request IDs include slashes
            service_request_id => { type => '/open311/regex', pattern => qr/^ [\w_\-\/]+ $/ax },
            # one backend, service codes have colons in
            update_id => { type => '/open311/regex', pattern => qr/^ [:\w_\-]+ $/ax },
        };
    },
);

sub requires_jurisdiction_ids { 1 }

sub _call {
    my ($self, $fn, $jurisdiction_id, @args) = @_;
    foreach ($self->plugins) {
        next unless $_->jurisdiction_id eq $jurisdiction_id;
        return $_->$fn(@args);
    }
}

sub services {
    my ($self, $args) = @_;
    return $self->_call('services', $args->{jurisdiction_id}, $args);
}

sub service {
    my ($self, $service_id, $args) = @_;
    return $self->_call('service', $args->{jurisdiction_id}, $service_id, $args);
}

sub post_service_request {
    my ($self, $service, $args) = @_;
    return $self->_call('post_service_request', $args->{jurisdiction_id},
        $service, $args);
}

sub get_token {
    my ($self, $token, $args) = @_;
    return $self->_call('get_token', $args->{jurisdiction_id},
        $token, $args);
}

sub service_request_content {
    my ($self, $args) = @_;
    return $self->_call('service_request_content', $args->{jurisdiction_id});
}

sub get_service_requests {
    my ($self, $args) = @_;
    return $self->_call('get_service_requests', $args->{jurisdiction_id},
        $args);
}

sub get_service_request {
    my ($self, $service_request_id, $args) = @_;
    return $self->_call('get_service_request', $args->{jurisdiction_id},
        $service_request_id, $args);
}

sub get_service_request_updates {
    my ($self, $args) = @_;
    return $self->_call('get_service_request_updates', $args->{jurisdiction_id},
        $args);
}

sub post_service_request_update {
    my ($self, $args) = @_;
    return $self->_call('post_service_request_update', $args->{jurisdiction_id},
        $args);
}

sub confirm_upload {
    my $self = shift;
    foreach ($self->plugins) {
        my $integs = [];
        if ( $_->can('get_integration') ) {
            push(@$integs, $_->get_integration) if $_->get_integration->isa('Integrations::Confirm');
        }
        if ($_->isa('Open311::Endpoint::Integration::Multi')) {
            foreach ($_->plugins) {
                if ( $_->can('get_integration') ) {
                    push(@$integs, $_->get_integration) if $_->get_integration->isa('Integrations::Confirm');
                }
            }
        }
        next unless @$integs;
        foreach my $integ (@$integs) {
            my $dir = $integ->config->{uploads_dir};
            # If the dir doesn't exist then it just means no files have been
            # uploaded yet, so carry on with the next plugin.
            next unless $dir && -d $dir;
            $dir = path($dir);

            foreach ($dir->children( qr/\.json$/ )) {
                my $id = $_->basename('.json');
                my $data = do {
                    my $fh = $_->openr_utf8;
                    local $/;
                    decode_json(scalar <$fh>);
                };

                my $success = $integ->upload_enquiry_documents($id, $data);
                if ($success) {
                    $dir->child($id)->remove_tree; # Files for upload
                    $_->remove;
                }
            }
        }
    }
}

sub check_endpoints {
    my ($self, $verbose) = @_;
    my @plugins = ();
    foreach ($self->plugins) {
        if ($_->isa('Open311::Endpoint::Integration::Multi')) {
            push @plugins, $_ foreach $_->plugins;
        } else {
            push @plugins, $_;
        }
    }
    my @urls = ();
    foreach (@plugins) {
        if ($_->can('get_integration')) {
            my $config = $_->get_integration->config;
            push @urls, $config->{api_url}          # Abavus, ATAK, Alloy, Boomi
                || $config->{endpoint_url}          # Confirm, Ezytreev, Symology, Uniform, WDM
                || $config->{endpoint}              # Salesforce
                || $config->{url}                   # Echo, Whitespace
                || $config->{jadu_api_base_url}     # Jadu
                || $config->{collective_endpoint};  # Bartec
        } elsif ($_->can('endpoint')) {
            push @urls, $_->endpoint;
        }
    }
    my %hosts;
    foreach (grep { $_ } @urls) {
        $hosts{URI->new($_)->host} = 1;
    }
    foreach (sort keys %hosts) {
        my $check = `openssl s_client -connect $_:443 < /dev/null 2>/dev/null| openssl x509 -checkend 604800 -noout`;
        next if $check =~ /will not expire/ && !$verbose;
        print "$_: $check";
    }
}

__PACKAGE__->run_if_script;
