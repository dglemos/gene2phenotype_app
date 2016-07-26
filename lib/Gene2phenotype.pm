package Gene2phenotype;
use Mojo::Base 'Mojolicious';
use Mojo::Home;
use Apache::Htpasswd;
#use File::Path qw(make_path remove_tree);
use File::Path;

use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::G2P::Utils::Downloads qw(download_data);

# This method will run once at server start
sub startup {
  my $self = shift;

# $self->secrets
# $self->app->sessions->cookie_name('moblo');
  $self->sessions->default_expiration(3600);

  my $config = $self->plugin('Config' => {file => $self->app->home .'/etc/gene2phenotype.conf'});
  my $password_file = $config->{password_file};
  my $downloads_dir = $config->{downloads_dir};
  my $registry_file = $config->{registry};
  my $public_folder = $config->{public_folder};
  my $static = $self->app->static();
  push @{$static->paths}, $public_folder;

  $self->plugin('CGI' => {
    before => sub {
      my $c = shift;
      $c->req->url->query->param(registry_file => $registry_file);
    },
  });
  $self->plugin('Model');
  $self->plugin('RenderFile');
  $self->plugin(mail => {
    from => 'anja@ebi.ac.uk',
    type => 'text/html',
  });

  $self->plugin('authentication' => {
    'load_user' => sub {
      my ($self, $uid) = @_;
      return $uid;
    },
    'validate_user' => sub {
      my ($self, $user, $pw) = @_;
      my $auth = new Apache::Htpasswd({ passwdFile => $password_file, ReadOnly => 1, UseMD5 => 1,});
      return $auth->htCheckPassword($user, $pw);
    },
  });

  $self->defaults(layout => 'base');
  $self->g2p_defaults($registry_file);

  my $r = $self->routes;

  $self->hook(before_dispatch => sub {
    my $c = shift;
    $c->stash(logged_in => $c->session('logged_in'));
  });

# redirect from old page:
  $r->get('/gene2phenotype/redirect')->to(template => 'redirect');

  $r->get('/gene2phenotype/gene2phenotype-webcode/*' => sub {
    my $c = shift;
    return $c->redirect_to('/gene2phenotype/redirect');
  });

  $r->get('/gene2phenotype')->to(template => 'home');
  $r->get('/gene2phenotype/disclaimer')->to(template => 'disclaimer');
  $r->get('/gene2phenotype/documentation')->to(template => 'documentation');
  $r->get('/gene2phenotype/help')->to(template => 'help');

  $r->get('/gene2phenotype/account')->to('login#account_info');
  $r->post('/gene2phenotype/account/update' => sub {
    my $c = shift;
    my $auth = new Apache::Htpasswd({ passwdFile => $password_file, ReadOnly => 0, UseMD5 => 1,});

    my $email = $c->param('email');
    my $current_pwd = $c->param('current_password');
    my $new_pwd = $c->param('new_password');
    my $retyped_pwd = $c->param('retyped_password');

    if (!$self->authenticate($email, $current_pwd)) { 
      $c->flash({message => 'Your current password is incorrect', alert_class => 'alert-danger'});
      return $c->redirect_to('/gene2phenotype/account');
    }

    if ($new_pwd ne $retyped_pwd) {
      $c->flash({message => 'Passwords don\'t match. Please ensure retyped password matches your new password.', alert_class => 'alert-danger'});
      return $c->redirect_to('/gene2phenotype/account');
    }

    my $success = $auth->htpasswd($email, $new_pwd, {'overwrite' => 1});        
    if ($success) {
      $c->flash({message => 'Successfully updated password', alert_class => 'alert-success'});
      return $c->redirect_to('/gene2phenotype/account');
    } else {
      $c->flash(message => 'Error occurred while resetting your password. Please contact g2p-help@ebi.ac.uk', alert_class => 'alert-danger');
      return $c->redirect_to('/gene2phenotype/account');
    }
  });
  $r->get('/gene2phenotype/login')->to(template => 'login/login');
  $r->get('/gene2phenotype/login/recovery')->to(template => 'login/recovery');
  $r->post('/gene2phenotype/login/recovery/mail')->to('login#send_recover_pwd_mail');
  $r->get('/gene2phenotype/login/recovery/reset')->to('login#validate_pwd_recovery');
  $r->post('/gene2phenotype/login/recovery/update' => sub {
    my $c = shift;
    my $auth = new Apache::Htpasswd({ passwdFile => $password_file, ReadOnly => 0, UseMD5 => 1,});
    my $email = $c->param('email');
    my $new_pwd = $c->param('new_password');
    my $retyped_pwd = $c->param('retyped_password');
    my $authcode = $c->param('authcode');
    my $saved_authcode = $c->session('code');
    my $saved_email = $c->session('email');
    if ($authcode eq $saved_authcode) {
      if ($new_pwd eq $retyped_pwd) {
        my $success = $auth->htpasswd($email, $new_pwd, {'overwrite' => 1});        
        $c->session(logged_in => 1);
        $c->stash(logged_in => 1);
        $c->flash({message => 'Successfully updated password', alert_class => 'alert-success'});
        return $c->redirect_to('/gene2phenotype');
      }
    }
    $c->flash(message => 'Error occurred while resetting your password. Please contact g2p-help@ebi.ac.uk', alert_class => 'alert-danger');
    return $c->redirect_to('/gene2phenotype');
  });

  $r->get('/gene2phenotype/reset')->to(template => 'login', change_pwd => 1);
  $r->get('/gene2phenotype/logout')->to('login#on_user_logout');
  
  $r->post('/gene2phenotype/login')->to('login#on_user_login');
  $r->post('/gene2phenotype/reset')->to('login#reset_pwd');

  $r->get('/gene2phenotype/gfd')->to('genomic_feature_disease#show');

# :action=add, delete, update, add_comment, delete_comment
  $r->get('/gene2phenotype/gfd/authorised/update')->to('genomic_feature_disease#update_visibility');
  $r->get('/gene2phenotype/gfd/category/update')->to('genomic_feature_disease#update');
  $r->get('/gene2phenotype/gfd/organ/update')->to('genomic_feature_disease#update_organ_list');
  $r->get('/gene2phenotype/gfd/attributes/:action')->to(controller => 'genomic_feature_disease_attributes');
  $r->get('/gene2phenotype/gfd/phenotype/:action')->to(controller => 'genomic_feature_disease_phenotype');
  $r->get('/gene2phenotype/gfd/publication/:action')->to(controller => 'genomic_feature_disease_publication');

  $r->get('/gene2phenotype/gene')->to('genomic_feature#show');
  $r->get('/gene2phenotype/disease')->to('disease#show');
  $r->get('/gene2phenotype/disease/update/')->to('disease#update');

  $r->get('/gene2phenotype/search')->to('search#results');
  $r->get('/cgi-bin/#script_name/*path_info' => {path_info => ''}, sub {
    my $c = shift;
    my $script_name = $c->stash('script_name');
    my $home =  $c->app->home;
    $c->cgi->run( script => "$home/cgi-bin/$script_name");
  });
  $r->get('/gene2phenotype/downloads')->to(template => 'downloads');
  $r->get('/gene2phenotype/downloads/#file_name' => sub {
    my $c = shift;
    my $file_name = $c->stash('file_name');
    $file_name =~ s/\.gz//;
    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
    my $stamp = join('_', ($mday, $mon, $hour, $min, $sec));
    my $tmp_dir = "$downloads_dir/$stamp";
    mkpath($tmp_dir);
    download_data($tmp_dir, $file_name, $registry_file);
    $c->render_file('filepath' => "$tmp_dir/$file_name.gz", 'filename' => "$file_name.gz", 'format' => 'zip', 'cleanup' => 1);
  });

}

sub g2p_defaults {
  my $self = shift;
  my $registry_file = shift; 
  my $registry = 'Bio::EnsEMBL::Registry';

  $registry->load_all($registry_file);
  my @panel_imgs = ();
  my $attribute_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'attribute');
  my $attribs = $attribute_adaptor->get_attribs_by_type_value('g2p_panel');
  foreach my $value (sort keys %$attribs) {
    push @panel_imgs,[
      $value => $value,
    ];
  }
  $self->defaults(panel_imgs => \@panel_imgs);
  $self->defaults(registry => $registry);
  $self->defaults(panel => 'ALL');
  $self->defaults(logged_in => 0);
  $self->defaults(alert_class => '');
}

1;
