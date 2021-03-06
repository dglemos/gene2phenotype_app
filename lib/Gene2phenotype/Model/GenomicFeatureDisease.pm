=head1 LICENSE
 
See the NOTICE file distributed with this work for additional information
regarding copyright ownership.
 
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
http://www.apache.org/licenses/LICENSE-2.0
 
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
 
=cut
package Gene2phenotype::Model::GenomicFeatureDisease; 
use Mojo::Base 'MojoX::Model';
sub fetch_by_dbID {
  my $self = shift;
  my $dbID = shift;
  my $logged_in = shift;

  my $registry = $self->app->defaults('registry');
  my $GFD_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'genomicfeaturedisease');
  my $GFD = $GFD_adaptor->fetch_by_dbID($dbID);

  my $GFDL_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'genomicfeaturediseaselog');
  my $user_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'user');

  my @logs = ();
  if ($logged_in) {
    my $GFD_logs = $GFDL_adaptor->fetch_all_by_GenomicFeatureDisease($GFD);  
    foreach my $log (@$GFD_logs) {
      my $created = $log->created;
      my $action = $log->action;
      my $user_id = $log->user_id;  
      my $user = $user_adaptor->fetch_by_dbID($user_id);
      my $user_name = $user->username;
      my $confidence_category = $log->confidence_category;
      push @logs, {created => $created, user => $user_name, confidence_category => $confidence_category, action => $action};
    }
  }

  my $panel = $GFD->panel;
  my $authorised = $GFD->is_visible;
  my $gene_symbol = $GFD->get_GenomicFeature->gene_symbol;
  my $gene_id = $GFD->get_GenomicFeature->dbID;

  my $disease_name = $GFD->get_Disease->name; 
  my $disease_id = $GFD->get_Disease->dbID;

  my $disease_name_synonyms = $self->_get_disease_name_synonyms($GFD);

#  my $disease_ontology_accessions = $self->_get_disease_ontology_accessions($GFD); 
  my $disease_ontology_accessions = []; 


  my $GFD_comments = $self->_get_GFD_comments($GFD);

  my $GFD_category = $self->_get_GFD_category($GFD);
  my $GFD_category_list = $self->_get_GFD_category_list($GFD);
  my $attributes = $self->_get_GFD_action_attributes($GFD, $logged_in);
  my $publications = $self->_get_publications($GFD);
  my $phenotypes = $self->_get_phenotypes($GFD);
  my $phenotype_ids_list = $self->get_phenotype_ids_list($GFD);
  my $organs = $self->_get_organs($GFD); 
  my $edit_organs = $self->_get_edit_organs($GFD, $organs, $panel); 

  my $add_GFD_action = $self->_get_GFD_action_attributes_list('add');
  my $add_AR_loop = $add_GFD_action->{AR};
  my $add_MC_loop = $add_GFD_action->{MC};
  my $gf_statistics = $self->_get_GF_statistics($GFD);

  return {
    panel => $panel,
    gene_symbol => $gene_symbol,
    gene_id => $gene_id,
    disease_name => $disease_name,
    disease_id => $disease_id,
    disease_name_synonyms => $disease_name_synonyms,
    ontology_accessions => $disease_ontology_accessions,
    authorised => $authorised,
    GFD_id => $dbID,
    GFD_category => $GFD_category,
    GFD_category_list => $GFD_category_list,
    GFD_actions => $attributes,
    GFD_comments => $GFD_comments,
    publications => $publications,
    phenotypes => $phenotypes,
    phenotype_ids_list => $phenotype_ids_list,
    organs => $organs,
    edit_organs => $edit_organs,
    add_AR_loop => $add_AR_loop,
    add_MC_loop => $add_MC_loop,
    logs => \@logs,
    statistics => $gf_statistics,
  };

}

sub duplicate {
  my $self = shift;
  my $GFD_id = shift;
  my $panel = shift;
  my $data = shift;
  my $email = shift;

  my $registry = $self->app->defaults('registry');
  my $GFD_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'genomicfeaturedisease');
  my $user_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'user');

  my $user = $user_adaptor->fetch_by_email($email);

  my $from_gfd = $GFD_adaptor->fetch_by_dbID($GFD_id);
 
  my $gf = $from_gfd->get_GenomicFeature;
  my $disease = $from_gfd->get_Disease;

  my $already_in_to_panel = $GFD_adaptor->fetch_by_GenomicFeature_Disease_panel($gf, $disease, $panel);
 
  if ($already_in_to_panel) {
    return [$already_in_to_panel, 'ENTRY_HAS_NOT_BEEN_DUPLICATED'];
  }
  
  # create new entry
  my $gfd_to_panel =  Bio::EnsEMBL::G2P::GenomicFeatureDisease->new(
    -panel => $panel,
    -disease_id => $disease->dbID,
    -genomic_feature_id => $gf->dbID,
    -confidence_category => $from_gfd->confidence_category,
    -adaptor => $GFD_adaptor,
  );
  $gfd_to_panel = $GFD_adaptor->store($gfd_to_panel, $user);
  
  foreach my $data_type (@$data) {
    if ($data_type eq 'gene_disease_attribs') {
      my $gfdaa = $registry->get_adaptor('human', 'gene2phenotype', 'GenomicFeatureDiseaseAction');

      # get all gene_disease_attribs 
      my $from_gfd_actions = $from_gfd->get_all_GenomicFeatureDiseaseActions;

      foreach my $from_gfd_action (@$from_gfd_actions) {
        my $new_GFD_action = Bio::EnsEMBL::G2P::GenomicFeatureDiseaseAction->new(
          -genomic_feature_disease_id => $gfd_to_panel->dbID,
          -allelic_requirement_attrib => $from_gfd_action->allelic_requirement_attrib,
          -mutation_consequence_attrib => $from_gfd_action->mutation_consequence_attrib,
          -user_id => undef,
        );
        $new_GFD_action = $gfdaa->store($new_GFD_action, $user);
      }
    } elsif ($data_type eq 'publications') {
      my $gfd_publication_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'GenomicFeatureDiseasePublication');
      my $from_gfd_publications = $from_gfd->get_all_GFDPublications;
      foreach my $from_gfd_publication (@$from_gfd_publications) {
        my $new_GFDPublication = Bio::EnsEMBL::G2P::GenomicFeatureDiseasePublication->new(
          -genomic_feature_disease_id => $gfd_to_panel->dbID,
          -publication_id => $from_gfd_publication->get_Publication->dbID,
          -adaptor => $gfd_publication_adaptor,
        );
        $gfd_publication_adaptor->store($new_GFDPublication);
      }
    } elsif ($data_type eq 'phenotypes') {
      my $gfd_phenotype_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'GenomicFeatureDiseasePhenotype');
      my $from_gfd_phenotypes = $from_gfd->get_all_GFDPhenotypes;
      foreach my $from_gfd_phenotype (@$from_gfd_phenotypes ) {
        my $new_GFDPhenotype = Bio::EnsEMBL::G2P::GenomicFeatureDiseasePhenotype->new(
          -genomic_feature_disease_id => $gfd_to_panel->dbID,
          -phenotype_id => $from_gfd_phenotype->get_Phenotype->dbID,
          -adaptor => $gfd_phenotype_adaptor,
        );
        $gfd_phenotype_adaptor->store($new_GFDPhenotype);
      }
    } elsif ($data_type eq 'organ_specificity') {
      my $gfd_organ_adaptor =  $registry->get_adaptor('human', 'gene2phenotype', 'GenomicFeatureDiseaseOrgan');
      my $from_gfd_organs = $from_gfd->get_all_GFDOrgans;
      foreach my $from_gfd_organ (@$from_gfd_organs) {
       my $new_GFDOrgan = Bio::EnsEMBL::G2P::GenomicFeatureDiseaseOrgan->new(
          -genomic_feature_disease_id => $gfd_to_panel->dbID,
          -organ_id => $from_gfd_organ->get_Organ->dbID,
          -adaptor => $gfd_organ_adaptor,
        );
        $gfd_organ_adaptor->store($new_GFDOrgan);
      }
    } else {
      
    }
  } 

  return [$gfd_to_panel, 'DUPLICATED_ENTRY_SUC']; 
}

sub fetch_all_by_panel_restricted {
  my $self = shift;
  my $panel = shift;
  my $registry = $self->app->defaults('registry');
  my $GFD_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'genomicfeaturedisease');
  my $gfds = $GFD_adaptor->fetch_all_by_panel_restricted($panel);
  my @results = ();
  foreach my $gfd (@$gfds) {
    push @results, {
      gene_symbol => $gfd->get_GenomicFeature->gene_symbol,
      disease_name => $gfd->get_Disease->name,
      GFD_id => $gfd->dbID,
    }; 
  }
  return \@results;
}

sub fetch_all_by_panel_without_publication {
  my $self = shift;
  my $panel = shift;
  my $registry = $self->app->defaults('registry');
  my $GFD_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'genomicfeaturedisease');
  my $gfds = $GFD_adaptor->fetch_all_by_panel_without_publications($panel);
  my @results = ();
  foreach my $gfd (@$gfds) {
    push @results, {
      gene_symbol => $gfd->get_GenomicFeature->gene_symbol,
      disease_name => $gfd->get_Disease->name,
      GFD_id => $gfd->dbID,
    }; 
  }
  return \@results;
}

sub fetch_all_duplicated_LGM_entries_by_panel {
  my $self = shift;
  my $panel = shift;
  my $registry = $self->app->defaults('registry');
  my $GFD_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'genomicfeaturedisease');
  my $merge_list = $GFD_adaptor->_get_all_duplicated_LGM_entries_by_panel($panel);
  return $merge_list;
}


sub get_allelic_requirement_by_attrib_ids {
  my $self = shift;
  my $attribs = shift;
  my @genotypes = ();
  my $registry = $self->app->defaults('registry');
  my $attribute_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'attribute');
  foreach my $attrib_id (split(',', $attribs)) {
    push @genotypes,  $attribute_adaptor->attrib_value_for_id($attrib_id);
  }
  return join(',', sort @genotypes);
}

sub get_allelic_requirement_attrib_ids_by_values {
  my $self = shift;
  my $values = shift;
  my @attrib_ids = ();
  my $registry = $self->app->defaults('registry');
  my $attribute_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'attribute');
  foreach my $value (split(',', $values)) {
    push @attrib_ids, $attribute_adaptor->attrib_id_for_type_value('allelic_requirement', $value);
  }
  return join(',', sort { $a <=> $b } @attrib_ids);
}

sub get_mutation_consequence_by_attrib_id {
  my $self = shift;
  my $attrib_id = shift;
  my $registry = $self->app->defaults('registry');
  my $attribute_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'attribute');
  return $attribute_adaptor->attrib_value_for_id($attrib_id);
}

sub get_mutation_consequence_attrib_id_by_value {
  my $self = shift;
  my $value = shift;
  my $registry = $self->app->defaults('registry');
  my $attribute_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'attribute');
  return $attribute_adaptor->attrib_id_for_type_value('mutation_consequence', $value);
}

sub get_confidence_value_by_attrib_id {
  my $self = shift;
  my $attrib_id = shift;
  my $registry = $self->app->defaults('registry');
  my $attribute_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'attribute');
  return $attribute_adaptor->attrib_value_for_id($attrib_id);
}

sub fetch_all_duplicated_LGM_entries_by_gene {
  my $self = shift;
  my $gf_id = shift;
  my $panel = shift;
  my $allelic_requirement_attrib = shift;
  my $mutation_consequence_attrib = shift;
  my $registry = $self->app->defaults('registry');
  my $GFD_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'genomicfeaturedisease');
  my $GF_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'genomicfeature');
  my $attribute_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'attribute');
  my $genotype = $attribute_adaptor->attrib_value_for_id($allelic_requirement_attrib);
  my $mechanism = $attribute_adaptor->attrib_value_for_id($mutation_consequence_attrib);

  my $genomic_feature = $GF_adaptor->fetch_by_dbID($gf_id);
  my $gene_symbol = $genomic_feature->gene_symbol;
  my $gfds = $GFD_adaptor->fetch_all_by_GenomicFeature_panel($genomic_feature, $panel); 

  my @entries = ();
  my @all_disease_names = ();

  my $phenotype_2_gfd_id = {};
  my $publication_2_gfd_id = {};

  my $gfd_id_2_disease_name = {};
  my $disease_name_2_gfd_id = {};

  foreach my $gfd (@$gfds) {
    my $gfd_actions = $gfd->get_all_GenomicFeatureDiseaseActions;
    next unless (grep {$_->allelic_requirement_attrib == $allelic_requirement_attrib && $_->mutation_consequence_attrib == $mutation_consequence_attrib} @$gfd_actions);

    my $gene_symbol = $gfd->get_GenomicFeature->gene_symbol; 
    my $disease_name = $gfd->get_Disease->name;
    my $disease_id = $gfd->get_Disease->dbID;
    push @all_disease_names, [$disease_name => $disease_id];
    my $gfd_id = $gfd->dbID;

    $gfd_id_2_disease_name->{$gfd_id} = $disease_name; 
    $disease_name_2_gfd_id->{$disease_name} = $gfd_id;

    my @actions = ();
    foreach my $gfd_action (@$gfd_actions) {
      my $allelic_requirement = $gfd_action->allelic_requirement;
      my $mutation_consequence = $gfd_action->mutation_consequence; 
      push @actions, "$allelic_requirement $mutation_consequence";
    }

    my @publications = ();  
    my $gfd_publications = $gfd->get_all_GFDPublications;
    foreach my $gfd_publication (@$gfd_publications) {
      my $publication =  $gfd_publication->get_Publication;
      my $title = $publication->title;
      if ($publication->source) {
        $title .= " " . $publication->source;
      }
      push @publications, $title;
      $publication_2_gfd_id->{$title}->{$gfd_id} = 1;
    }

    my @phenotypes = ();
    my $gfd_phenotypes = $gfd->get_all_GFDPhenotypes;
    foreach my $gfd_phenotype (@$gfd_phenotypes) {
      my $name = $gfd_phenotype->get_Phenotype->name;
      push @phenotypes, $name;
      $phenotype_2_gfd_id->{$name}->{$gfd_id} = 1;
    }

    push @entries, {
      gene_symbol => $gene_symbol,
      disease_name => $disease_name,
      gfd_id => $gfd_id,
      actions => \@actions,
      phenotypes => \@phenotypes,
      publications => \@publications,
    };
  
  }

  my @all_phenotypes = keys %$phenotype_2_gfd_id;
  my @all_publications = keys %$publication_2_gfd_id;

  my @sorted_all_disease_names = sort {$a->[0] cmp $b->[0]} @all_disease_names;
  return {
    gene_symbol => $gene_symbol,
    genotype => $genotype,
    mechanism => $mechanism, 
    gf_id => $gf_id,
    panel => $panel,
    mc_attrib => $mutation_consequence_attrib,
    ar_attrib => $allelic_requirement_attrib,
    entries => \@entries,
    all_disease_name_2_id => \@sorted_all_disease_names,
    all_phenotypes => \@all_phenotypes,
    all_publications => \@all_publications,
    phenotype_2_gfd_id => $phenotype_2_gfd_id,
    publication_2_gfd_id => $publication_2_gfd_id,
    gfd_id_2_disease_name => $gfd_id_2_disease_name,
    disease_name_2_gfd_id => $disease_name_2_gfd_id,
  };
}

sub merge_all_duplicated_LGM_by_panel_gene {
  my $self = shift;
  my $email = shift;
  my $gf_id = shift;
  my $disease_id = shift;
  my $panel = shift;
  my $gfd_ids = shift;

  my $registry = $self->app->defaults('registry');
  my $GFD_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'genomicfeaturedisease');
  my $user_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'user');
  my $user = $user_adaptor->fetch_by_email($email);

  my $gfd = $GFD_adaptor->_merge_all_duplicated_LGM_by_panel_gene($user, $gf_id, $disease_id, $panel, $gfd_ids);

  return $gfd;
}

sub fetch_by_panel_GenomicFeature_Disease {
  my $self = shift;
  my $panel = shift;
  my $gf = shift;
  my $disease = shift;
  my $registry = $self->app->defaults('registry');
  my $GFD_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'genomicfeaturedisease');
  my $attribute_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'attribute');
  my $panel_id = $attribute_adaptor->attrib_id_for_value($panel); 
  my $gfd = $GFD_adaptor->fetch_by_GenomicFeature_Disease_panel_id($gf, $disease, $panel_id);
  return $gfd;
}

sub fetch_all_existing_by_panel_LGM {
  my $self = shift;
  my $panel = shift;
  my $gf = shift;
  my $ar_attrib_ids = shift;
  my $mc_attrib_id = shift;
  my $registry = $self->app->defaults('registry');
  my $GFD_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'genomicfeaturedisease');

  my $attribute_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'attribute');
  my $gfds = $GFD_adaptor->fetch_all_by_GenomicFeature_panel($gf, $panel);
  my @existing_gfds = ();
  foreach my $gfd (@{$gfds}) {
    my $actions = $gfd->get_all_GenomicFeatureDiseaseActions;
    foreach my $action (@$actions) {
      if ($action->allelic_requirement_attrib eq $ar_attrib_ids && $action->mutation_consequence_attrib eq $mc_attrib_id) {
        push @existing_gfds, {
          gfd_id => $gfd->dbID,
          gene_symbol => $gfd->get_GenomicFeature->gene_symbol,
          disease_name => $gfd->get_Disease->name,
          allelic_requirement => $action->allelic_requirement,
          mutation_consequence => $action->mutation_consequence, 
          panel => $gfd->panel,
        };
      }     
    }
  }
  return \@existing_gfds;
}

sub add {
  my $self = shift;
  my $panel = shift;
  my $genomic_feature = shift;
  my $disease = shift;
  my $allelic_requirement_attrib_ids = shift;
  my $mutation_consequence_attrib_id = shift;
  my $confidence_attrib_id = shift;
  my $email = shift;

  my $registry = $self->app->defaults('registry');
  my $GFD_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'genomicfeaturedisease');
  my $attribute_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'attribute');
  my $user_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'user');

  my $panel_id = $attribute_adaptor->attrib_id_for_type_value('g2p_panel', $panel); 

  my $gfd =  Bio::EnsEMBL::G2P::GenomicFeatureDisease->new(
    -panel_attrib => $panel_id,
    -disease_id => $disease->dbID,
    -genomic_feature_id => $genomic_feature->dbID,
    -confidence_category_attrib => $confidence_attrib_id,
    -adaptor => $GFD_adaptor,
  );
  my $user = $user_adaptor->fetch_by_email($email);
  $gfd = $GFD_adaptor->store($gfd, $user);

  my $GFDAction_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'GenomicFeatureDiseaseAction');
  my $GFDAction = Bio::EnsEMBL::G2P::GenomicFeatureDiseaseAction->new(
    -genomic_feature_disease_id => $gfd->dbID(),
    -mutation_consequence_attrib => $mutation_consequence_attrib_id,
    -allelic_requirement_attrib => $allelic_requirement_attrib_ids,
  );
  $GFDAction_adaptor->store($GFDAction, $user);

  return $gfd;
}

sub add_by_name {
  my ($self, $panel, $gene_symbol, $disease_name, $genotypes, $mutation_consequence, $confidence_value, $email) = @_;
  my $registry = $self->app->defaults('registry');
  my $attribute_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'attribute');
  my $panel_id = $attribute_adaptor->attrib_id_for_type_value('g2p_panel', $panel); 
  my $confidence_attrib_id = $attribute_adaptor->attrib_id_for_type_value('confidence_category', $confidence_value);
  
  my $genomic_feature_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'GenomicFeature');
  my $genomic_feature = $genomic_feature_adaptor->fetch_by_gene_symbol($gene_symbol);
  my $disease_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'Disease'); 
  my $disease = $disease_adaptor->fetch_by_name($disease_name);

  my $user_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'user');
  my $user = $user_adaptor->fetch_by_email($email);

  my $GFD_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'genomicfeaturedisease');

  my $gfd =  Bio::EnsEMBL::G2P::GenomicFeatureDisease->new(
    -panel_attrib => $panel_id,
    -disease_id => $disease->dbID,
    -genomic_feature_id => $genomic_feature->dbID,
    -confidence_category_attrib => $confidence_attrib_id,
    -adaptor => $GFD_adaptor,
  );
  $gfd = $GFD_adaptor->store($gfd, $user);

  my $allelic_requirement_attrib_ids = $self->get_allelic_requirement_attrib_ids_by_values($genotypes);
  my $mutation_consequence_attrib_id = $self->get_mutation_consequence_attrib_id_by_value($mutation_consequence);

  my $GFDAction_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'GenomicFeatureDiseaseAction');
  my $GFDAction = Bio::EnsEMBL::G2P::GenomicFeatureDiseaseAction->new(
    -genomic_feature_disease_id => $gfd->dbID(),
    -mutation_consequence_attrib => $mutation_consequence_attrib_id,
    -allelic_requirement_attrib => $allelic_requirement_attrib_ids,
  );
  $GFDAction_adaptor->store($GFDAction, $user);
  return $gfd;
}

sub delete {
  my $self = shift;
  my $email = shift;
  my $GFD_id = shift;

  my $registry = $self->app->defaults('registry');
  my $GFD_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'genomicfeaturedisease');
  my $user_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'user');
  my $user = $user_adaptor->fetch_by_email($email);
  my $GFD = $GFD_adaptor->fetch_by_dbID($GFD_id); 
  $GFD_adaptor->delete($GFD, $user);
}

sub get_confidence_values {
  my $self = shift;
  my $registry = $self->app->defaults('registry');
  my $attribute_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'attribute');
  my $attribs = $attribute_adaptor->get_attribs_by_type_value('confidence_category');
  my @list = ();
  foreach my $value (sort keys %$attribs) {
    my $id = $attribs->{$value};
    push @list, [$value => $id];
  }
  return \@list;
}

sub get_genotypes {
  my $self = shift;
  my $registry = $self->app->defaults('registry');
  my $attribute_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'attribute');
  my $attribs = $attribute_adaptor->get_attribs_by_type_value('allelic_requirement');
  my @AR_tmpl = ();
  foreach my $value (sort keys %$attribs) {
    my $id = $attribs->{$value};
    push @AR_tmpl, {
      AR_attrib_id => $id,
      AR_attrib_value => $value,
    };
  }
  return \@AR_tmpl;
}

sub get_mutation_consequences {
  my $self = shift;
  my $registry = $self->app->defaults('registry');
  my $attribute_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'attribute');
  my $attribs = $attribute_adaptor->get_attribs_by_type_value('mutation_consequence');
  my @MC_tmpl = ();
  foreach my $value (sort keys %$attribs) {
    my $id = $attribs->{$value};
    push @MC_tmpl, [$value => $id];
  }
  return \@MC_tmpl;
}

sub _get_GFD_category_list {
  my $self = shift;
  my $GFD = shift;
  my $GFD_category = $GFD->confidence_category;
  my $GFD_id = $GFD->dbID;
  my $registry = $self->app->defaults('registry');
  my $attribute_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'attribute');
  my $attribs = $attribute_adaptor->get_attribs_by_type_value('confidence_category');
  my @list = ();
  foreach my $value (sort keys %$attribs) {
    my $id = $attribs->{$value};
    my $is_selected =  ($value eq $GFD_category) ? 'selected' : '';
    if ($is_selected) {
      push @list, [$value => $id, selected => $is_selected];
    } else {
      push @list, [$value => $id];
    }
  }
  return \@list;
}

sub _get_GFD_category {
  my $self = shift;
  my $GFD = shift;
  my $category = $GFD->confidence_category || 'Not assigned';
  return $category;
}

sub _get_disease_name_synonyms {
  my $self = shift;
  my $GFD = shift;
  my @synonyms = ();
  my $gfd_disease_synonyms = $GFD->get_all_GFDDiseaseSynonyms;
  foreach my $gfd_disease_synonym (sort {$a->synonym cmp $b->synonym} @{$gfd_disease_synonyms}) {
    push @synonyms, {
      synonym => $gfd_disease_synonym->synonym,
      gfd_disease_synonym_id => $gfd_disease_synonym->dbID,
    };
  }
  return \@synonyms;
}

sub _get_GFD_action_attributes_list {
  my $self = shift;
  my $type = shift;
  my $GFD_action = shift;

  my @ARs = ();
  my $mutation_consequence = '';
  if ($type eq 'edit') {
    @ARs = split(',', $GFD_action->allelic_requirement);
    $mutation_consequence = $GFD_action->mutation_consequence;
  }

  my $registry = $self->app->defaults('registry');
  my $attribute_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'attribute');
  my $attribs = $attribute_adaptor->get_attribs_by_type_value('allelic_requirement');
  my @AR_tmpl = ();
  foreach my $value (sort keys %$attribs) {
    my $id = $attribs->{$value};
    if ($type eq 'edit') {
      my $checked = (grep $_ eq $value, @ARs) ? 'checked' : '';
      push @AR_tmpl, {
        AR_attrib_id => $id,
        AR_attrib_value => $value,
        checked => $checked,
      };
    } else {
      push @AR_tmpl, {
        AR_attrib_id => $id,
        AR_attrib_value => $value,
      };
    }
  }

  $attribs = $attribute_adaptor->get_attribs_by_type_value('mutation_consequence');
  my @MC_tmpl = ();
  foreach my $value (sort keys %$attribs) {
    my $id = $attribs->{$value};
    if ($type eq 'edit') {
      my $selected = ($value eq $mutation_consequence) ? 'selected' : undef;
      if ($selected) {
        push @MC_tmpl, [$value => $id, selected => $selected];
      } else {
        push @MC_tmpl, [$value => $id];
      }
    } else {
      push @MC_tmpl, [ $value => $id ];
    }
  }
  return {AR => \@AR_tmpl, MC => \@MC_tmpl};
}

sub _get_GFD_action_attributes {
  my $self = shift;
  my $GFD = shift;
  my $logged_in = shift;
  my $registry = $self->app->defaults('registry');
  my $GFDAL_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'genomicFeatureDiseaseActionLog');
  my $user_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'user');

  my $GFD_actions = $GFD->get_all_GenomicFeatureDiseaseActions();
  my @actions = ();

  foreach my $gfda (@$GFD_actions) {
    my @logs = ();
    if ($logged_in) {
      my $gfda_logs = $GFDAL_adaptor->fetch_all_by_GenomicFeatureDiseaseAction($gfda);
      foreach my $log (@$gfda_logs) {
        my $created = $log->created;
        my $user_id = $log->user_id;
        my $user = $user_adaptor->fetch_by_dbID($user_id);
        my $user_name = $user->username;
        my $action = $log->action;
        my $allelic_requirement = $log->allelic_requirement || 'Not assigned';
        my $mutation_consequence = $log->mutation_consequence || 'Not assigned';
        push @logs, {created => $created, user => $user_name, ar => $allelic_requirement, mc => $mutation_consequence, action => $action};
      }
    }
    my $allelic_requirement = $gfda->allelic_requirement || 'Not assigned';
    my $mutation_consequence_summary = $gfda->mutation_consequence || 'Not assigned';
    my $edit_GFD_action = $self->_get_GFD_action_attributes_list('edit', $gfda);
    push @actions, {
      allelic_requirement => $allelic_requirement,
      mutation_consequence_summary => $mutation_consequence_summary,
      AR_loop => $edit_GFD_action->{AR},
      MC_loop => $edit_GFD_action->{MC},
      GFD_action_id => $gfda->dbID,
      logs => \@logs,
    };
  }

  return \@actions;
}
sub _get_disease_ontology_accessions {
  my $self = shift;
  my $GFD = shift;
  my $registry = $self->app->defaults('registry');
  my $ontology_term_adaptor = $registry->get_adaptor('Multi', 'Ontology', 'OntologyTerm');

  my $disease = $GFD->get_Disease;
  my $accessions = $disease->ontology_accessions;
  my @ontology_accessions_tmpl = ();

  foreach my $accession (@$accessions) {
    my $term = $ontology_term_adaptor->fetch_by_accession($accession);
    if ($term) {
      my $term_name = $term->name;
      my $term_source = $term->ontology;     
      push @ontology_accessions_tmpl, {
        accession => $accession,
        name => $term_name,
        source => $term_source,      
      };
    } else {
      push @ontology_accessions_tmpl, {
        accession => $accession,
      };
    }
  }

  @ontology_accessions_tmpl = sort {$a->{name} cmp $b->{name}} @ontology_accessions_tmpl; 

  return \@ontology_accessions_tmpl;
}

sub _get_publications {
  my $self = shift;
  my $GFD = shift;
  my @publications = ();

  my $registry = $self->app->defaults('registry');
  my $phenotype_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'phenotype');
  my $GFD_phenotype_adaptor =  $registry->get_adaptor('human', 'gene2phenotype', 'GenomicFeatureDiseasePhenotype');

  my $GFD_publications = $GFD->get_all_GFDPublications;
  foreach my $GFD_publication (sort {$a->get_Publication->title cmp $b->get_Publication->title} @$GFD_publications) {
    my $publication = $GFD_publication->get_Publication;
    my @GFD_phenotype_ids = map {$_->phenotype_id} @{$GFD_phenotype_adaptor->fetch_all_by_GenomicFeatureDisease($GFD)};

    my $comments = $GFD_publication->get_all_GFDPublicationComments;
    my @comments_tmpl = ();
    foreach my $comment (@$comments) {
      push @comments_tmpl, {
        user => $comment->get_User()->username,
        date => $comment->created,
        comment_text => $comment->comment_text,
        GFD_publication_comment_id => $comment->dbID,
        GFD_id => $GFD->dbID,
      };
    }
    my $pmid = $publication->pmid;
    my $title = $publication->title;
    my $source = $publication->source;

    $title ||= 'PMID:' . $pmid;
    $title .= " ($source)" if ($source);

    push @publications, {
      comments => \@comments_tmpl,
      title => $title,
      pmid => $pmid,
      GFD_publication_id => $GFD_publication->dbID,
      GFD_id => $GFD->dbID,
    };
  }
  return \@publications;
}

sub _get_GFD_comments {
  my $self = shift;
  my $GFD = shift;
  my @comments = ();
  my $GFD_comments = $GFD->get_all_GFDComments;  
  foreach my $comment (@$GFD_comments) {
    push @comments, {
      user => $comment->get_User()->username,
      date => $comment->created,
      comment_text => $comment->comment_text,
      GFD_comment_id => $comment->dbID,
      GFD_id => $GFD->dbID,
    };
  }
  return \@comments;
}

sub _get_phenotypes {
  my $self = shift;
  my $GFD = shift;

  my @phenotypes = ();
  my $GFD_phenotypes = $GFD->get_all_GFDPhenotypes;
  foreach my $GFD_phenotype ( sort { $a->get_Phenotype()->name() cmp $b->get_Phenotype()->name() } @$GFD_phenotypes) {
    my $phenotype = $GFD_phenotype->get_Phenotype;
    my $stable_id = $phenotype->stable_id;
    my $name = $phenotype->name;
    my $comments = $GFD_phenotype->get_all_GFDPhenotypeComments;
    my @comments_tmpl = ();
    foreach my $comment (@$comments) {
      push @comments_tmpl, {
        user => $comment->get_User()->username,
        date => $comment->created,
        comment_text => $comment->comment_text,
        GFD_phenotype_comment_id => $comment->dbID,
        GFD_id => $GFD->dbID,
      };
    }

    push @phenotypes, {
      comments => \@comments_tmpl,
      stable_id => $stable_id,
      name => $name,
      GFD_phenotype_id => $GFD_phenotype->dbID,
    };
  }
  my @sorted_phenotypes = sort {$a->{name} cmp $b->{name}} @phenotypes;
  return \@phenotypes;
}

sub _get_organs {
  my $self = shift;
  my $GFD = shift;
  my @organ_list = ();
  my $organs = $GFD->get_all_GFDOrgans;
  foreach my $organ (@$organs) {
    my $name = $organ->get_Organ()->name;
    push @organ_list, $name;
  }
  return \@organ_list;
}

sub _get_edit_organs {
  my $self = shift;
  my $GFD = shift;  
  my $organ_list = shift;
  my $panel_name = shift;
 
  my $registry = $self->app->defaults('registry');
  my $organ_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'Organ');
  my $panel_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'panel');
  my $panel = $panel_adaptor->fetch_by_name($panel_name);

  my %all_organs = map {$_->name => $_->dbID} @{$organ_adaptor->fetch_all_by_panel_id($panel->dbID)};
  my @organs = (); 
  foreach my $value (sort keys %all_organs) {
    my $id = $all_organs{$value};
    my $checked = (grep $_ eq $value, @$organ_list) ? 'checked' : '';
    push @organs, {
      organ_id => $id,
      organ_name => $value,
      checked => $checked,
    };
  }
  return \@organs;
}

sub _get_GF_statistics {
  my $self = shift;
  my $GFD = shift;
  my $registry = $self->app->defaults('registry');
  my $genomic_feature_statistic_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'GenomicFeatureStatistic');
  my $GF = $GFD->get_GenomicFeature;
  my $panel_attrib = $GFD->panel_attrib;
  my $genomic_feature_statistics = $genomic_feature_statistic_adaptor->fetch_all_by_GenomicFeature_panel_attrib($GF, $panel_attrib);

  if (scalar @$genomic_feature_statistics) {
    my @statistics = ();
    foreach (@$genomic_feature_statistics) {
      my $clustering = ( $_->clustering) ? 'Mutatations are considered clustered.' : '';
      push @statistics, {
        'p-value' => $_->p_value,
        'dataset' => $_->dataset,
        'clustering' => $clustering,
      }
    }
    return \@statistics;
  }
  return [];
}


sub get_phenotype_ids_list {
  my $self = shift;
  my $GFD = shift;
  my @phenotype_ids = ();
  my $GFDPhenotypes = $GFD->get_all_GFDPhenotypes;
  foreach my $GFDPhenotype (@$GFDPhenotypes) {
    push @phenotype_ids, $GFDPhenotype->get_Phenotype->dbID;
  }
  return join(',', @phenotype_ids);
}

sub update_GFD_category {
  my $self = shift;
  my $email = shift;
  my $GFD_id = shift;
  my $category_attrib_id = shift;
  my $registry = $self->app->defaults('registry');
  my $GFD_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'GenomicFeatureDisease');
  my $user_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'user');
  my $user = $user_adaptor->fetch_by_email($email);
  my $GFD = $GFD_adaptor->fetch_by_dbID($GFD_id);
  $GFD->confidence_category_attrib($category_attrib_id);
  $GFD_adaptor->update($GFD, $user); 
}

sub update_disease {
  my $self = shift;
  my $email = shift;
  my $GFD_id = shift;
  my $disease_id = shift;
  my $disease_name = shift;
  my $disease_mim = shift;
  
  my $registry = $self->app->defaults('registry');
  my $disease_adaptor =  $registry->get_adaptor('human', 'gene2phenotype', 'Disease');
  my $disease = $disease_adaptor->fetch_by_dbID($disease_id);
  if ($disease->name ne $disease_name || ($disease->mim && $disease->mim ne $disease_mim)) {

    my $GFD_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'GenomicFeatureDisease');
    my $user_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'user');
    my $user = $user_adaptor->fetch_by_email($email);
    $disease =  Bio::EnsEMBL::G2P::Disease->new(
      -name => $disease_name,
      -mim => $disease_mim,
      -adaptor => $disease_adaptor,
    );
    $disease = $disease_adaptor->store($disease);
    my $GFD = $GFD_adaptor->fetch_by_dbID($GFD_id);
    $GFD->disease_id($disease->dbID);
    $GFD_adaptor->update($GFD, $user); 
  }
}

sub update_organ_list {
  my $self = shift;
  my $email = shift;
  my $GFD_id = shift;
  my $organ_id_list = shift;

  my $registry = $self->app->defaults('registry');
  my $GFDOrgan_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'GenomicFeatureDiseaseOrgan');
  my $user_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'user');
  my $user = $user_adaptor->fetch_by_email($email);

  $GFDOrgan_adaptor->delete_all_by_GFD_id($GFD_id);
  foreach my $organ_id (split(',', $organ_id_list)) {
    my $GFDOrgan =  Bio::EnsEMBL::G2P::GenomicFeatureDiseaseOrgan->new(
      -organ_id => $organ_id,
      -genomic_feature_disease_id => $GFD_id,
      -adaptor => $GFDOrgan_adaptor, 
    );
    $GFDOrgan_adaptor->store($GFDOrgan);
  }  
}

sub update_visibility {
  my $self = shift;
  my $email = shift;
  my $GFD_id = shift;
  my $visibility = shift;

  my $registry = $self->app->defaults('registry');
  my $GFD_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'GenomicFeatureDisease');
  my $user_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'user');
  my $user = $user_adaptor->fetch_by_email($email);

  my $is_visible = $visibility eq 'authorised' ? 1 : 0;
  my $GFD = $GFD_adaptor->fetch_by_dbID($GFD_id);
  $GFD->is_visible($is_visible);
  $GFD_adaptor->update($GFD, $user); 
}

1;
