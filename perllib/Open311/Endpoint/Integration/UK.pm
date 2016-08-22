package Open311::Endpoint::Integration::UK;

use Moo;
extends 'Open311::Endpoint';

use Types::Standard ':all';
use Module::Pluggable
    search_path => ['Open311::Endpoint::Integration::UK'],
    instantiate => 'new';

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

sub post_service_request {
    my ($self, $service, $args) = @_;
    return $self->_call('post_service_request', $args->{jurisdiction_id},
        $service, $args);
}

__PACKAGE__->run_if_script;
