package Open311::Endpoint::Service;
use Moo;
use MooX::HandlesVia;
use Types::Standard ':all';
use namespace::clean;

has service_name => (
    is => 'ro',
    isa => Str,
);

has service_code => (
    is => 'ro',
    isa => Str,
);

has default_service_notice => (
    is => 'ro',
    isa => Maybe[Str],
    predicate => 1,
);

has description => (
    is => 'ro',
    isa => Str,
);

has keywords => (
    is => 'ro',
    isa => ArrayRef[Str],
    default => sub { [] },
);

has group => (
    is => 'rw',
    isa => Str,
    default => '',
);

has type => (
    is => 'ro',
    isa => Enum[qw/ realtime batch blackbox /],
    default => 'realtime',
);

has attributes => (
    is => 'lazy',
    isa => ArrayRef[ InstanceOf['Open311::Endpoint::Service::Attribute'] ],
    handles_via => 'Array',
    handles => {
        has_attributes => 'count',
        get_attributes => 'elements',
    }
);

sub _build_attributes { [] }

1;
