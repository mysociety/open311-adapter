package Open311::Endpoint::Integration::UK;

use Moo;
extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';

use Types::Standard ':all';
use Module::Pluggable
    search_path => ['Open311::Endpoint::Integration::UK'],
    max_depth => 5,
    instantiate => 'new';
use JSON::MaybeXS;
use Path::Tiny;

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
            # some service codes have spaces
            service_code => { type => '/open311/regex', pattern => qr/^ [\w_\- \/\(\)]+ $/ax },
            # some request IDs include slashes
            service_request_id => { type => '/open311/regex', pattern => qr/^ [\w_\-\/]+ $/ax },
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
                my $data = decode_json($_->slurp_utf8);
                my $success = $integ->upload_enquiry_documents($id, $data);
                if ($success) {
                    $dir->child($id)->remove_tree; # Files for upload
                    $_->remove;
                }
            }
        }
    }
}

__PACKAGE__->run_if_script;
