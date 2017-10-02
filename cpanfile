# setenv script
requires 'List::MoreUtils', '>= 0.425';
requires 'local::lib';
requires 'Class::Unload';

# Application
requires 'Carp';
requires 'Data::Dumper';
requires 'Data::Rx';
requires 'DateTime';
requires 'DateTime::Format::Oracle';
requires 'DateTime::Format::W3CDTF', '>= 0.07';
# requires 'DBD::Oracle';
requires 'DBI';
requires 'Encode';
requires 'JSON::MaybeXS';
requires 'List::Util';
requires 'Module::Pluggable';
requires 'Moo';
requires 'Moo::Role';
requires 'MooX::HandlesVia';
requires 'namespace::autoclean';
requires 'Path::Tiny';
requires 'Scalar::Util';
requires 'SOAP::Lite';
requires 'Starman';
requires 'Types::Standard';
requires 'XML::Simple';
requires 'Web::Simple';
requires 'YAML';

# Modules used by the test suite
requires 'LWP::Protocol::PSGI';
requires 'Module::Loaded';
requires 'Test::Exception';
requires 'Test::LongString';
requires 'Test::MockModule';
requires 'Test::MockTime';
requires 'Test::More';
