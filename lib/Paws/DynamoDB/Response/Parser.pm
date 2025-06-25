package Paws::DynamoDB::Response::Parser;

use strict;
use warnings;
use Carp qw(croak);
use Scalar::Util qw(blessed);

our $VERSION = '0.01';

=head1 NAME

Paws::DynamoDB::Response::Parser - Convert Paws DynamoDB response objects to Perl data structures.

=head1 SYNOPSIS

  use Paws::DynamoDB::Response::Parser;

  my $parser   = Paws::DynamoDB::Response::Parser->new;
  my $dynamodb = Paws->service('DynamoDB',
     region    => 'eu-west-1',
     endpoint  => 'http://localhost:4566'
  );
  my $response = $dynamodb->Scan(TableName => "Users");
  my $data     = $parser->to_perl($response);

=head1 DESCRIPTION

This module converts Paws::DynamoDB response objects into native Perl data structures,
handling all DynamoDB attribute types (S, N, B, M, L etc.).

=cut

=head1 METHODS

=head2 new()

Creates a new parser instance.

=cut

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

=head2 to_perl($response)

Converts Paws DynamoDB response object to a Perl data structure.

Supported response types:

- GetItemOutput
- ScanOutput
- QueryOutput
- BatchGetItemOutput

=cut

sub to_perl {
    my ($self, $response) = @_;

    unless (blessed($response)) {
        croak "Invalid response object";
    }

    if ($response->isa('Paws::DynamoDB::GetItemOutput')) {
        return $response->Item ? $self->_unwrap_item($response->Item) : undef;
    }
    elsif ($response->isa('Paws::DynamoDB::ScanOutput') ||
           $response->isa('Paws::DynamoDB::QueryOutput')) {
        my $items = $response->Items || [];
        return [ map { $self->_unwrap_item($_) } @$items ];
    }
    elsif ($response->isa('Paws::DynamoDB::BatchGetItemOutput')) {
        return $self->_process_batch_response($response);
    }

    croak "Unsupported response type: " . ref($response);
}

#
#
# PRIVATE SUBROUTINES

sub _process_batch_response {
    my ($self, $response) = @_;

    my @all_items;

    # Process Responses
    if ($response->Responses && blessed($response->Responses)) {
        my $responses_map = $response->Responses->Map;
        foreach my $table_name (keys %$responses_map) {
            my $table_items = $responses_map->{$table_name};
            if (ref $table_items eq 'ARRAY') {
                push @all_items, map { $self->_unwrap_item($_) } @$table_items;
            }
        }
    }

    return \@all_items;
}

sub _unwrap_item {
    my ($self, $item) = @_;
    return undef unless defined $item
                        && blessed($item)
                        && $item->isa('Paws::DynamoDB::AttributeMap');

    my %unwrapped;
    my $item_map = $item->Map;
    foreach my $key (keys %$item_map) {
        $unwrapped{$key} = $self->_unwrap_attribute($item_map->{$key});
    }
    return \%unwrapped;
}

sub _unwrap_attribute {
    my ($self, $attr) = @_;

    return undef unless defined $attr
                        && blessed($attr)
                        && $attr->isa('Paws::DynamoDB::AttributeValue');

    if    (defined $attr->S)      { return $attr->S;     }
    elsif (defined $attr->N)      { return $attr->N + 0; }
    elsif (defined $attr->BOOL)   { return $attr->BOOL;  }
    elsif (defined $attr->NULL)   { return undef;        }
    elsif (defined $attr->B)      { return $attr->B;     }
    elsif (defined $attr->M)      {
        my %map;
        foreach my $key (keys %{$attr->M}) {
            $map{$key} = $self->_unwrap_attribute($attr->M->{$key});
        }
        return \%map;
    }
    elsif (defined $attr->L)      {
        return [ map { $self->_unwrap_attribute($_) } @{$attr->L} ];
    }
    elsif (defined $attr->SS)     { return $attr->SS; }
    elsif (defined $attr->NS)     { return [ map { $_ + 0 } @{$attr->NS} ]; }
    elsif (defined $attr->BS)     { return $attr->BS; }

    croak "Unsupported attribute type: " . Dumper($attr);
}

1;

=head1 AUTHOR

Mohammad Sajid Anwar <mohammad.anwar@yahoo.com>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
