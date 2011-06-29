package ACIS::UserData::Data::Record;    ### -*-perl-*-  
#
#  This file is part of ACIS software, http://acis.openlib.org/
#
#  Description:
#
#    ARDB-Record class for ACIS user-provided data-records.
#    Implements ARDB::Record interface,
#    http://acis.openlib.org/dev/ardb-record.html
#
#
#  Copyright (C) 2003 Ivan Baktcheev, Ivan Kurmanov for ACIS project,
#  http://acis.openlib.org/
#
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License, version 2, as
#  published by the Free Software Foundation.
# 
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
# 
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
#
#  ---
#  $Id$
#  ---



use strict;

use base ( 'ARDB::Record' );


use Carp::Assert;


sub id {
  my $self = shift;
  assert( $self-> {id} );
  
  return $self -> {id};
}

# ������� ������������� ������/�������.

sub type {
  return 'acis-record-person';
}


#use UNIVERSAL qw( isa );


sub get_value {
  my $self = shift;
  my $path = shift;
  
  my $data = $self;

  my @steps2 = my @steps = split '/', $path;

  foreach ( @steps ) {
    my $step = shift @steps2;

    if ( not ref $data 
         or ( # UNIVERSAL::isa( $data, 'HASH' )
             ref($data) eq 'HASH' 
             and not exists $data ->{$_} )
       ) {
      return ();
    } 

    if (# UNIVERSAL::isa( $data, 'ARRAY' ) ) {
        ref($data) eq 'ARRAY' ) {
      my $further = join '/', $step, @steps2;
      my @r;
      foreach ( @$data ) {
        push @r, get_value( $_, $further );
      }
      return @r;
    }

    $data = $data -> {$_};
  }
  
  if (# UNIVERSAL::isa( $data, 'ARRAY' ) ) { 
      ref($data) eq 'ARRAY') { 
    return @$data; 
  }
  
  return $data;
}

# ������� ������ �������� �� ���� ������, ��������������� ������������
# SPEC ��� ������ ������. ������������ SPEC ������� �� ������������
# ARDB. ������ �� ���������� ������� �������� XPath, ���� author/name,
# �� � �����-�� ��� ���� ���� - ����� ��������� ������������ -- ���
# �������, ��� �� ����� ������������ ��� �������-����������� �������.

# ������, ������������ ARDB ��� get_unfolded_record() ������

sub add_relationship {

  my $self     = shift;
  my $relation = shift;
  my $object   = shift;
  
  my $relations = $self -> {'ardb-record'} {relations};
  
  if ( ref $relations -> {$relation} eq 'ARRAY' ) {
    push @{$relations -> {$relation}}, $object;

  } else {
    $relations -> {$relation} = [];
    push @{$relations -> {$relation}}, $object;
  } 
}

# ��������� ������ ���������� � ������ ��������. ������ ��� ����,
# ����� ������������ ARDB ���� ��������������� ���� ��������
# ������������ � ������, ��� ������������ ��� ������ �������� � ���
# �����-�� ���������... ��� ��������� �� �� ���� ������ -- ��� ��
# ���� ����.

sub set_view {
  my $self = shift;
  my $view = shift;
  
  $self -> {'ardb-record'} {view} = $view;
}

# �������� "�����������" �������, � ����� ���� �� ����� �������
# ������������.

# ���������������� ������
sub view {
  my $self = shift;
  
  return $self -> {'ardb-record'}  {view};
}
# ����� ������������ ��� ������, � ����� ���� ��� ������. ����������
# ������.

sub get_relationship {
  my $self     = shift;
  my $relation = shift;
  
  my $relations = $self -> {'ardb-record'}  {relations};
  
  if ( ref $relations -> {$relation} eq 'ARRAY' ) {
    return @{ $relations -> {$relation} };

  } else {
    return undef;
  } 
}
# ����� ������������ ��� ������, � ����� ��������� �������� ���
# ������. ���������� ������ ��������.
1;
