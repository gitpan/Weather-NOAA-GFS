package Weather::NOAA::GFS;

#use 5.006;
use strict;
use warnings;

use LWP::UserAgent;
use Net::FTP;
use HTML::LinkExtractor;
use Data::Dumper;
use Time::Local;

require Exporter;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw ( idrisi2png ascii2idrisi downloadGribFiles grib2ascii);
our $VERSION   = "0.04";

# VERSION 0.03
#	- no Perl Version check

# VERSION 0.04
#	- added gradsc_path parameter
#	- added wgrib_path parameter
#	- documentation corrections



my $LOGFILE = "forecast.log";
my $URL_NOMAD_1_SH = "http://nomad2.ncep.noaa.gov/cgi-bin/ftp2u_avn.sh";
my $CERCO_FTP = 'ftp://nomad2.ncep.noaa.gov/pub/NOMAD_3hr/';

#------------------------------------------------------------------------
# Constructor
#------------------------------------------------------------------------
sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self  = {};

	# some general attributes
	$self->{PROXY}   = "none";
	$self->{TIMEOUT} = 180;
	$self->{DEBUG}   = 0;
 	$self->{LOGFILE}   = undef;
	$self->{TEMP_DIR}  = undef;
	$self->{MAIL_ANONYMOUS} = undef;#obbligatorio

	# quadro
	$self->{MINLON}  = undef;#obbligatorio
	$self->{MAXLON}  = undef;#obbligatorio
	$self->{MINLAT}  = undef;#obbligatorio
	$self->{MAXLAT}  = undef;#obbligatorio
	$self->{D_LAT}  = undef;#Delta Lat
	$self->{D_LON}  = undef;#Delta Lon
	
	$self->{RESOLUTION}  = 1;
	$self->{GRIB_FILES}  = {};
	$self->{START_TIME}  = time;# serve per cronometrare il tempo del processo
	$self->{SETUP} = 0; # definisce se l'istanza è andata a buon fine e a superato i check
	
	# parameters provided by new method
	my %parameters = ();
	if ( ref( $_[0] ) eq "HASH" ) {
		%parameters = %{ $_[0] };
	} else {
		%parameters = @_;
	}

	# set attributes as in %parameters
	$self->{PROXY}       = $parameters{proxy}   if ( $parameters{proxy} );
	$self->{TIMEOUT}     = $parameters{timeout} if ( $parameters{timeout} );
	$self->{DEBUG}       = $parameters{debug}   if ( $parameters{debug} );
	$self->{MINLON}       = $parameters{minlon}   if ( $parameters{minlon} );
	$self->{MAXLON}       = $parameters{maxlon}   if ( $parameters{maxlon} );
	$self->{MINLAT}       = $parameters{minlat}   if ( $parameters{minlat} );
	$self->{MAXLAT}       = $parameters{maxlat}   if ( $parameters{maxlat} );
	$self->{LOGFILE}       = $parameters{logfile}   if ( $parameters{logfile} );
	$self->{TEMP_DIR}       = $parameters{temp_dir}   if ( $parameters{temp_dir} );
	$self->{MAIL_ANONYMOUS}       = $parameters{mail_anonymous}   if ( $parameters{mail_anonymous} );
	$self->{CBARN_PATH}       = $parameters{cbarn_path}   if ( $parameters{cbarn_path} );	
	$self->{R_PATH}       = $parameters{r_path}   if ( $parameters{r_path} );
	$self->{GRADSC_PATH}       = $parameters{gradsc_path}   if ( $parameters{gradsc_path} );
	$self->{WGRIB_PATH}       = $parameters{wgrib_path}   if ( $parameters{wgrib_path} );	




	bless( $self, $class );
	if($self->{MAIL_ANONYMOUS}){
		$self->_debug( "mail Ok!");
	} else {
		$self->_debug( "'mail_anonymous' is a mandatory parameter!");
		exit
	}
	if($self->{GRADSC_PATH}){
		$self->_debug( "mail Ok!");
	} else {
		$self->_debug( "'gradsc_path' is a mandatory parameter!");
		exit
	}
	if($self->{WGRIB_PATH}){
		$self->_debug( "mail Ok!");
	} else {
		$self->_debug( "'wgrib_path' is a mandatory parameter!");
		exit
	}
	
	if($self->_check_area_size()) {
		$self->_debug("area check Ok!");
		$self->{SETUP} = 1;
# 		if($self->check_string_on_url("mages","http://www.google.com")){
# 			$self->_debug( "string checked!");
# 		} else {
# 			$self->_debug( "string check FAILED!");
# 		}

		#inizio procedura di scarico
# 		if($self->_grib_download()){
# 			$self->_debug( "download succeded!");
# 			#go on
# 		} else {
# 			$self->_debug( "download FAILED!");
# 		}
		
		#procedura grib2r
# 		$self->_grib2r();
		
	} else {
		$self->_debug( "area check FAILED!");
		exit
	}
	
	$self->_debug( Dumper($self) );

	return $self;
}

#------------------------------------------------------------------------
# other internals
#------------------------------------------------------------------------
sub _debug {
	my $self   = shift;
	my $notice = shift;
	my $now = $self->data_formattata_forecast(time);
	if ( $self->{LOGFILE} ) {
		my $filename = $self->{LOGFILE};
		open(LOGFILE, ">>$filename");
		print LOGFILE "$now - $notice\n";
	}
	if ( $self->{DEBUG} ) {
		#warn ref($self) . " - $now - DEBUG NOTE: $notice\n";
		warn "$now - $notice\n";
		return 1;
	}
	return 0;
}



sub _check_area_size {
	my $self   = shift;
	my $error = 0;
	#estraggo i valori assoluti delle coordinate
	my $a_minlat = $self->absolute_integer_value($self->{MINLAT});
	my $a_minlon = $self->absolute_integer_value($self->{MINLON});
	my $a_maxlat = $self->absolute_integer_value($self->{MAXLAT});
	my $a_maxlon = $self->absolute_integer_value($self->{MAXLON});
	my $d_lat = $self->absolute_integer_value($self->{MAXLAT} - $self->{MINLAT}) + 1;
	my $d_lon = $self->absolute_integer_value($self->{MAXLON} - $self->{MINLON}) +1;
	
	#$self->_debug("Vars:".$self->{MINLAT}."-".$self->{MINLON}."-".$self->{MAXLAT}."-".$self->{MAXLON}."-".$d_lat."-".$d_lon);
	#$self->_debug("Vars:".$a_minlat."-".$a_minlon."-".$a_maxlat."-".$a_maxlon."-".$d_lat."-".$d_lon);
	
	#controllo che minimi e massimi siano rispettati;
	if($self->{MINLAT}>=$self->{MAXLAT}) {
		$self->_debug("Minlat non puo' essere maggiore di Maxlat");
		$error = 1;
	} 
	if($self->{MINLON}>=$self->{MAXLON}) {
		$self->_debug("Minlon non puo' essere maggiore di Maxlon");
		$error = 1;
	} 
	 
	
	#controllo che le coordinate cadano nel range delle coordinate sferiche
	if($a_minlat>90) {
		$self->_debug("Minlat non puo' avere un valore assoluto superiore a 90");
		$error = 1;
	} 
	if($a_maxlat>90) {
		$self->_debug("Maxlat non puo' avere un valore assoluto superiore a 90");
		$error = 1;
	} 
	if($a_minlon>180) {
		$self->_debug("Minlon non puo' avere un valore assoluto superiore a 180");
		$error = 1;
	} 
	if($a_maxlon>180) {
		$self->_debug("Maxlon non puo' avere un valore assoluto superiore a 180");
		$error = 1;
	}
	#controllo che il valore assoluto fra massimi e minimi sia superiore a ...
	## NOTA -> Capecchi -> è giusta questa cosa?
	if($d_lat<10) {
		$self->_debug("Il valore assoluto della differenza fra Maxlat e Minlat deve essere superiore a 10");
		$error = 1;
	}
	if($d_lon<10) {
		$self->_debug("Il valore assoluto della differenza fra Maxlon e Minlon deve essere superiore a 10");
		$error = 1;
	}
	
	#controllo che l'area richiesta abbiamo un'estensione minima superiore a 100 pixel
	if($d_lat*$d_lon<200) {
		$self->_debug("l'area richiesta deve essere superiore a 200 pixel");
		$error = 1;
	} else {
		$self->{D_LAT} = $d_lat;
		$self->{D_LON} = $d_lon;
	}
	
	
	
	if($error==1){
		return 0;
	} else {
		#$self->_debug("Area size is OK");
		return 1;
	}
}

sub checkSetup {
	my $self = shift;
	
	if(!$self->{SETUP}){
		return 0;
	}
	
	return 1;
}

#net stuff

sub check_string_on_url {
	my $self = shift;
        my $string = shift;#arg0
        my $url = shift;#arg1
        
        use LWP;
        my $useragent = LWP::UserAgent->new;
        my $request = new HTTP::Request('GET',$url);
        my $response = $useragent->request($request);
        my $stringa_html = $response->as_string();
	#if ( $self->{DEBUG} ) {$self->_debug($stringa_html);}
        if(index($stringa_html,$string) > 0){
                return 1
        } else {
                return
        }
}


sub get_ftp_dir {
	my $self = shift;
        my $ftp_da_cercare = shift;
        my $url = shift;
	
	my $ftp_founded = undef;
	my $useragent = LWP::UserAgent->new;
        my $request = new HTTP::Request('GET',$url);
        my $response = $useragent->request($request);
        my $html = $response->as_string();
	
	my $LX = new HTML::LinkExtractor();
	$LX->parse(\$html);

	foreach my $Link (@{$LX->links} ){
	## becco solo l'ftp che presenta la sola directory (ovvero non contiene il file "gblav*")
		if( ($$Link{href}=~ /^ftp:\/\//) && ($$Link{href}!~ /gblav/) ) {	
			$ftp_founded = $$Link{_TEXT};		
			$ftp_founded =~ s/<([a-z][a-z0-9]*)[^>]*>(.*?)<\/a>/$2/;
		}
	}
	
	undef $LX;
       	#
       	##RITORNA OUTPUT FUNCTION
       	if ($ftp_founded) {
       		return $ftp_founded;
       	} else {
       		return;
       	}
}


sub scarica_da_ftp {
	#
	##ARGV
	my $self = shift;
	my $ftp_site = shift;
	#
	
	##variables
	my @lista_grib = undef;
	my $ftp = undef;
	
	##Module
	use Net::FTP;
	$self->_debug("scarico_da_ftp - ftpsite: ".$ftp_site);
	###############################################################
	my $ftp_senza_ftp = $ftp_site;
	my $prefisso_ftp = 'ftp://';
	$ftp_senza_ftp =~ s/$prefisso_ftp//g;
	my @lista_dir = split(/\//,$ftp_senza_ftp);
	###############################################################

	#
	##ISTANZIA OGGETTO FTP
	if (!($ftp = Net::FTP->new($lista_dir[0], timeout=>3600))) {
		$self->_debug("scarico_da_ftp: Non riesco a collegarmi con ftp $lista_dir[0]");
	}
#######	$ftp = Net::FTP->new("$lista_dir[0]", timeout=>3600) || $self->_debug("Non riesco a collegarmi con ftp $lista_dir[0]");
  	#
  	##CONNECT & LOGIN
  	if (!($ftp->login('anonymous','pippo@topolino.org'))) {
		$self->_debug("scarico_da_ftp: Non riesco login con ftp $lista_dir[0]");
	} else {
  		$self->_debug("scarico_da_ftp: Collegato e loggato su ftp $lista_dir[0] per scaricare grib files");
	}
#######	$ftp->login('anonymous','pippo@topolino.org')|| $self->_debug("Non riesco login con ftp $lista_dir[0]");
####### ###print STDOUT "\n***\tCOLLEGATO CON $lista_dir[0]\t***\n";
####### $self->_debug("Collegato e loggato su ftp $lista_dir[0] per scaricare grib files");
	#
	##CHANGE DIR
  	my $new_dir='/'."$lista_dir[1]".'/'."$lista_dir[2]".'/'."$lista_dir[3]".'/';
  	if (!($ftp->cwd("$new_dir"))) {
		$self->_debug("scarico_da_ftp: Non riesco a cambiare dir in $lista_dir[0]");
	} else {
  		$self->_debug("scarico_da_ftp: Cambiata directory in $new_dir");
	}
#######	$ftp->cwd("$new_dir") || $self->_debug("Non riesco a cambiare dir in $lista_dir[0]");
#######	$self->_debug("Cambiata directory in $new_dir");
  	
  	##GET FILES
  	if (!($ftp->binary)) {
		$self->_debug("scarico_da_ftp: Non riesco a cambiare in binary mode");
	} else {
  		$self->_debug("scarico_da_ftp: Switch to binary mode");
	}
	if (!( @lista_grib= $ftp->ls("gblav*pgrbf*"))) {
		$self->_debug("scarico_da_ftp: Non riesco retrieve lista grib files");
	} else {
  		$self->_debug("scarico_da_ftp: Retrieve grib files array");
	}
#######	$ftp->binary;	
#######	@lista_grib=$ftp->ls("gblav*pgrbf*");
  	my $tot_gfiles=  $#lista_grib+1;
	my $prog=0;
  	foreach my $gfile (@lista_grib) {
  		while (!($ftp->get("$gfile"))) {
  			if (!($ftp = Net::FTP->new("$lista_dir[0]", timeout=>3600))) {
				$self->_debug("scarico_da_ftp: Non riesco a collegarmi con ftp $lista_dir[0]");
				return;
			}
			if (!( $ftp->login('anonymous',$self->{MAIL_ANONYMOUS}))) {
				$self->_debug("scarico_da_ftp: Non riesco login con ftp $lista_dir[0]");
				return;
			} else {
		  		$self->_debug("scarico_da_ftp: Collegato e loggato su ftp $lista_dir[0] per scaricare grib files");
			}
			if (!($ftp->cwd("$new_dir"))) {
				$self->_debug("scarico_da_ftp: Non riesco a cambiare dir in $lista_dir[0]");
				return;
			} else {
		  		$self->_debug("scarico_da_ftp: Cambiata directory in $new_dir");
			}
			if (!($ftp->binary)) {
				$self->_debug("scarico_da_ftp: Non riesco a cambiare in binary mode");
				return;
			} else {
		  		$self->_debug("scarico_da_ftp: Switch to binary mode");
			}
			if (!($ftp->get("$gfile"))) {
				$self->_debug("scarico_da_ftp: Non riesco a scaricare grib file $gfile");
				return;
			}
#######			$ftp = Net::FTP->new("$lista_dir[0]", timeout=>3600) || $self->_debug("Non riesco a collegarmi con ftp $lista_dir[0]");
#######			$ftp->login('anonymous','pippo@topolino.org')|| $self->_debug("Non riesco login con ftp $lista_dir[0]");
#######			$ftp->cwd("$new_dir") || $self->_debug("Non riesco a cambiare dir in $lista_dir[0]");
#######			$ftp->binary;
#######			$ftp->get("$gfile");
  		}	
  		$self->_debug("scarico_da_ftp: $gfile downloaded");
  		my $rimanenti = $#lista_grib-$prog;
  		###print STDOUT "***\tRimangono da scaricare $rimanenti files\t***\n\n";
  		$prog++;
	}
	#
	##QUIT
	$ftp->quit;		
}


sub downloadGribFiles {
	my $self = shift;
	
	if($self->{SETUP}!=1){
		$self->_debug( "downloadGribFiles: Setup is not proper. Control input data and try again.");
		return 0;
	}
	my @gribs = glob 'gblav.t*z.pgrbf*'; #elenca tutti i grib files presenti nella cartella corrente

	## VARS
	my $ftp_trovato = undef;
	

	my $STRINGA_URL = "http://nomad2.ncep.noaa.gov/cgi-bin/ftp2u_avn.sh?file=gblav\.t00z\.pgrbf03&file=gblav\.t00z\.pgrbf06&file=gblav\.t00z\.pgrbf09&file=gblav\.t00z\.pgrbf12&file=gblav\.t00z\.pgrbf15&file=gblav\.t00z\.pgrbf18&file=gblav\.t00z\.pgrbf21&file=gblav\.t00z\.pgrbf24&file=gblav\.t00z\.pgrbf27&file=gblav\.t00z\.pgrbf30&file=gblav\.t00z\.pgrbf33&file=gblav\.t00z\.pgrbf36&file=gblav\.t00z\.pgrbf39&file=gblav\.t00z\.pgrbf42&file=gblav\.t00z\.pgrbf45&file=gblav\.t00z\.pgrbf48&file=gblav\.t00z\.pgrbf51&file=gblav\.t00z\.pgrbf54&file=gblav\.t00z\.pgrbf57&file=gblav\.t00z\.pgrbf60&file=gblav\.t00z\.pgrbf63&file=gblav\.t00z\.pgrbf66&file=gblav\.t00z\.pgrbf69&file=gblav\.t00z\.pgrbf72&file=gblav\.t00z\.pgrbf75&file=gblav\.t00z\.pgrbf78&file=gblav\.t00z\.pgrbf81&file=gblav\.t00z\.pgrbf84&file=gblav\.t00z\.pgrbf87&file=gblav\.t00z\.pgrbf90&file=gblav\.t00z\.pgrbf93&file=gblav\.t00z\.pgrbf96&file=gblav\.t00z\.pgrbf99&file=gblav\.t00z\.pgrbf102&file=gblav\.t00z\.pgrbf105&file=gblav\.t00z\.pgrbf108&file=gblav\.t00z\.pgrbf111&file=gblav\.t00z\.pgrbf114&file=gblav\.t00z\.pgrbf117&file=gblav\.t00z\.pgrbf120&file=gblav\.t00z\.pgrbf123&file=gblav\.t00z\.pgrbf126&file=gblav\.t00z\.pgrbf129&file=gblav\.t00z\.pgrbf132&file=gblav\.t00z\.pgrbf135&file=gblav\.t00z\.pgrbf138&file=gblav\.t00z\.pgrbf141&file=gblav\.t00z\.pgrbf144&file=gblav\.t00z\.pgrbf147&file=gblav\.t00z\.pgrbf150&file=gblav\.t00z\.pgrbf153&file=gblav\.t00z\.pgrbf156&file=gblav\.t00z\.pgrbf159&file=gblav\.t00z\.pgrbf162&file=gblav\.t00z\.pgrbf165&file=gblav\.t00z\.pgrbf168&file=gblav\.t00z\.pgrbf171&file=gblav\.t00z\.pgrbf174&file=gblav\.t00z\.pgrbf177&file=gblav\.t00z\.pgrbf180&wildcard=&lev_sfc=on&lev_1000_mb=on&lev_925_mb=on&lev_850_mb=on&var_APCP=on&var_PRES=on&var_RH=on&var_UGRD=on&var_VGRD=on&var_TMP=on&subregion=on&leftlon=$self->{MINLON}&rightlon=$self->{MAXLON}&toplat=$self->{MAXLAT}&bottomlat=$self->{MINLAT}&results=SAVE&rtime=3hr&machine=149.139.16.204&user=anonymous&passwd=&ftpdir=%2Fincoming_1hr&prefix=&dir=";
	
	#$self->_debug("Stringa Url: ".$STRINGA_URL);
	
	while ($#gribs<59) {
 		my $tot_gribs=$#gribs+1;
 		 $self->_debug( "GRIB files in dir: $tot_gribs:60");
	
		if($self->check_string_on_url("transferred 60 out of 60 files",$STRINGA_URL)){	
			 $ftp_trovato = $self->get_ftp_dir($CERCO_FTP,$STRINGA_URL);
			 $self->_debug("ftp_trovato: ".$ftp_trovato);	
			if (length($ftp_trovato) > 0 ) {
				$self->scarica_da_ftp($ftp_trovato);
			} else {
				$self->_debug("Errore nella ricerca del ftp per grib files");
			}	  
		} else {
			if ($self->check_string_on_url("Sorry, machine is overloaded",$STRINGA_URL)) {
				$self->_debug("Server $URL_NOMAD_1_SH overloaded");
			} elsif ($self->check_string_on_url("out of disk space",$STRINGA_URL)) {
				$self->_debug("Server $URL_NOMAD_1_SH ran out of disk space");
			} elsif ($self->check_string_on_url("too many ftp2u jobs now",$STRINGA_URL)) {
				$self->_debug("Server $URL_NOMAD_1_SH too many ftp2u jobs now");
			} else {
				$self->_debug("Errore sconosciuto in fase di scarico grib files");
			}
			
		}
	
  @gribs = glob 'gblav.t*z.pgrbf*';
  $tot_gribs=$#gribs+1;
  $self->_debug( "GRIB files in dir: $tot_gribs:60");
  ## LORE -> note -> Ci vuole un delay parametrizzato per non stressare il server
  
  }
  
  ## LORE -> note ->Ci vuole un temporizzatore che capisca quando il server non ne vuole sapere di darci i file. DOpo qualche ora
  			# dobbiamo abbozzarla di tentare lo scarico.
 
 if($#gribs==59){
 	$self->{GRIB_FILES} = 'gblav.t*z.pgrbf*';
	return 1;
 } else {
 	return 0;
 }

}  

sub ascii2idrisi {

	my $self = shift;
	
	if(!$self->checkSetup()){
		$self->_debug( "ascii2idrisi: Setup is not proper. Control input data and try again.");
		return 0;
	}
	
	my %chiaveValore= ();
	#$self->{GRIB_FILES} = 'gblav.t*z.pgrbf*';
		my @grib_files = glob 'gblav.t*z.pgrbf*';
		#estraggo lo header del grib_file riga per riga
		my $wgrib_path = $self->{WGRIB_PATH};
		my @grib_vars = `$wgrib_path -v $grib_files[0]`;
		
		foreach my $line (@grib_vars) {
			if($#grib_vars==0) {
				next; #la prima riga deve essere saltata ("OUTPUT WGRIB -V")
			}
			my @elementi = split /:/,$line;
			my $i = undef;
			my $key = undef;
			my $value = undef;
			for($i=0;$i<=$#elementi;$i++){
				## NOTA -> LORE -> attento al  valore "sfc" (ma forse non è un problema)
				if($i==3){
					#CHIAVE
					$key = $elementi[$i];	
				}
				if($i==4){
					#VALORE
					my @valori = split / /,$elementi[$i];
					$value = $valori[0];# becco solo il primo valore (es: "850 mb" -> 850; "sfc" -> sfc )
				}
			}
			
			$self->_debug(  " ascii2idrisi -chiave: $key, value: $value\n");
			if($key=~/APCP/){
				$self->ascii2idrisi_avarage($key,$value);
				for(my $a=1;$a<=7;$a++){
					my $key2 = $key.$a;
					$self->_debug(  "ascii2idrisi - chiave: $key2, value: $value\n");
					$self->ascii2idrisi_avarage($key2,$value);
				}
			} else {
				$self->ascii2idrisi_avarage($key,$value);
			}
			#$chiaveValore{$key}=$value;
		}
	
	#print "totale: ".@sgribbed_files."\n\n";
	return 1;
}

sub idrisi2png {

	my $self = shift;
	
	if(!$self->checkSetup()){
		return 0;
	}
	
	my @idrisi_files = glob 'media_*.rdc';
	#$self->_debug( "idrisi2png");
	foreach my $idrisi_file (@idrisi_files) {
		#$self->_debug( "$idrisi_file");
		my @elementi = split /_/,$idrisi_file;
		my $key = undef;
		my $value = undef;
		for(my $i=0;$i<=$#elementi;$i++){
			
			if($i==1){
				$key = $elementi[$i];
			}
			
			if($i==2){
				#my @elementi2 = split /./,$idrisi_file;
				$value = $elementi[$i];
				$value =~ s/[\.\,][a-z]+//;
			}
			
		}
		$self->_debug( "idrisi2png - key:$key - value:$value");
		$self->idrisi2png_exe($key,$value);
		
	}
	return 1;
}


sub grib2ascii {

	my $self = shift;
	
	if(!$self->checkSetup()){
		return 0;
	}
	
	#$self->{GRIB_FILES} = 'gblav.t*z.pgrbf*';
	my @grib_files = glob 'gblav.t*z.pgrbf*';
	#estraggo lo header del grib_file riga per riga
	my $wgrib_path = $self->{WGRIB_PATH};
	my @grib_vars = `$wgrib_path -v $grib_files[0]`;
	#my @grib_vars = `wgrib -v $grib_files[0]`;

	#VARS
	my @text_files;
# 	OUTPUT WGRIB -V	
# 	1:0:D=2004111700:TMP:1000 mb:kpds=11,100,1000:3hr fcst:"Temp. [K]
# 	2:1852:D=2004111700:TMP:925 mb:kpds=11,100,925:3hr fcst:"Temp. [K]
# 	3:3704:D=2004111700:TMP:850 mb:kpds=11,100,850:3hr fcst:"Temp. [K]
# 	4:5556:D=2004111700:RH:1000 mb:kpds=52,100,1000:3hr fcst:"Relative humidity [%]
# 	5:7186:D=2004111700:RH:925 mb:kpds=52,100,925:3hr fcst:"Relative humidity [%]
# 	6:8816:D=2004111700:RH:850 mb:kpds=52,100,850:3hr fcst:"Relative humidity [%]
# 	7:10446:D=2004111700:UGRD:1000 mb:kpds=33,100,1000:3hr fcst:"u wind [m/s]
# 	8:12298:D=2004111700:UGRD:925 mb:kpds=33,100,925:3hr fcst:"u wind [m/s]
# 	9:14150:D=2004111700:UGRD:850 mb:kpds=33,100,850:3hr fcst:"u wind [m/s]
# 	10:16002:D=2004111700:VGRD:1000 mb:kpds=34,100,1000:3hr fcst:"v wind [m/s]
# 	11:17854:D=2004111700:VGRD:925 mb:kpds=34,100,925:3hr fcst:"v wind [m/s]
# 	12:19926:D=2004111700:VGRD:850 mb:kpds=34,100,850:3hr fcst:"v wind [m/s]
# 	13:21778:D=2004111700:PRES:sfc:kpds=1,1,0:3hr fcst:"Pressure [Pa]
# 	14:25176:D=2004111700:TMP:sfc:kpds=11,1,0:3hr fcst:"Temp. [K]
# 	15:27248:D=2004111700:APCP:sfc:kpds=61,1,0:0-3hr acc:"Total precipitation [kg/m^2]
	
	my $index = 0;
	foreach my $grib_file (@grib_files) {
		foreach my $line (@grib_vars) {
			#$self->_debug($line);
			if($#grib_vars==0) {
				next; #la prima riga deve essere saltata ("OUTPUT WGRIB -V")
			}
			my @elementi = split /:/,$line;
			my $i = undef;
			my $key = undef;
			my $value = undef;
			for($i=0;$i<=$#elementi;$i++){
				## NOTA -> LORE -> attento al  valore "sfc" (ma forse non è un problema)
				if($i==3){
					#CHIAVE
					$key = $elementi[$i];	
				}
				if($i==4){
					#VALORE
					my @valori = split / /,$elementi[$i];
					$value = $valori[0];# becco solo il primo valore (es: "850 mb" -> 850; "sfc" -> sfc )
				}
			}
			$self->_debug("Grib2ascii: $key-> $value");
			## Creo i files temporanei
			my $txt_file=$grib_file;
			$txt_file =~ s/\./_/g;
			$txt_file=$txt_file."_".$key."-".$value."\.txt";
			#$self->_debug("nome file: ".$txt_file);
			push(@text_files,$txt_file); 
			#$self->_debug("wgrib -s $grib_file | egrep \":$key:$value\" | wgrib -i -grib $grib_file -text -o $txt_file");
			system($self->{WGRIB_PATH}." -s $grib_file | egrep \":$key:$value\" | ".$self->{WGRIB_PATH}." -i -grib $grib_file -text -o $txt_file");
			
			#all'ultimo giro creo i valori aggregati
# 			if($index==@friends){
# 				 #$self->_agregated_values($key,$value);
# 			}	 

			
		}
	$index++;	
	}
	return 1;
}




sub ascii2idrisi_avarage {

	my $self = shift;
	my $key = shift;
	my $value = shift;
# 	my $key = @_[0];
# 	my $value = @_[1];
	my $real_key = undef;

	
	if($key =~ /APCP/) {
		$real_key = 'APCP';
	} else {
		$real_key = $key;
	}
	my $glob_match = 'gblav_t*z_pgrbf*_'.$real_key.'-'.$value.'.txt';
	#print $glob_match."\n";
	my @sgribbed_files = glob $glob_match;

		
	# apro il file di output finale -> aggregazione dati
	my $nome_file_out = "media_".$key."_".$value."\.rst";#binario
	my $nome_file_rdc = "media_".$key."_".$value."\.rdc";#ascii infos (raster documentation file)
	

	my $index = 0;
	my $index2 = 0;
	my @values;
	
	#Praparo l'array dei files->valori
	foreach my $sgribbed_file (@sgribbed_files) {
		open (FIN,"<$sgribbed_file");
		$index2=0;
		
		while (<FIN>) {
			$values[$index][$index2] = $_;
			$index2++;
		}
		close(FIN);
		$index++;
	}
	
	open(FOUT,">$nome_file_out") || print "Non apre file out ($nome_file_out) \n";
	
	binmode(FOUT);
	
	
	#variabili coordinate
	my $lon_i = 0;
	my $col = $self->{D_LON};
	my $rig = $self->{D_LAT};

	my $minlon= $self->{MINLON};
	my $maxlon= $self->{MAXLON};
	my $minlat= $self->{MINLAT};
	my $maxlat = $self->{MAXLAT};
	
	my $res = $self->{RESOLUTION};
	
	my $lon = $minlon;
	my  $lat = $maxlat;
	my $min_value = 1000000;
	my $max_value = -100000;

	my $test_i = 0;
	for (my $i1=0;$i1<$index2;$i1++) { 
	##NOTA -> LORE -> per output binary non mettere lo header
		if($i1==0) {
			#stampo lo header per R solo al primo ciclo dove ho un grib file
# 			my $header="x\ty\tvariab";
# 			print FOUT "$header\n";
# 			next;
			
		} else {
			my $tot = 0;
			my $i3 = 0;
			my $tot_apcp1 = 0;
			my $tot_apcp2 = 0;
			my $tot_apcp3 = 0;
			my $tot_apcp4 = 0;
			my $tot_apcp5 = 0;
			my $tot_apcp6 = 0;
			my $tot_apcp7 = 0;
			
			for (my $i2=0;$i2<$index;$i2++) {
				my $value_line = $values[$i2][$i1];
				#$value=sprintf("%5.1f",$value);
				
				$tot = $tot + $value_line;
				if($i2>=0 && $i2 <=7) {
					$tot_apcp1 = $tot;
				}
				if($i2>=8 && $i2 <=15) {
					$tot_apcp2 = $tot;
				}
				if($i2>=16 && $i2 <=23) {
					$tot_apcp3 = $tot;
				}
				if($i2>=24 && $i2 <=31) {
					$tot_apcp4 = $tot;
				}
				if($i2>=32 && $i2 <=39) {
					$tot_apcp5 = $tot;
				}
				if($i2>=40 && $i2 <=47) {
					$tot_apcp6 = $tot;
				}
				if($i2>=48 && $i2 <=55) {
					$tot_apcp7 = $tot;
				}
				$i3++;
			}
			#print "key aggragated: $key";
			if ($key  eq 'APCP') {
				#sommo tutto e non non divido
				$tot = $tot;
# 				print $tot." ";
			}
			if ($key  eq 'APCP1') {
				#somma della pioggia del prima giorno
				$tot = $tot_apcp1;
				#print $tot." ";
			}
			if ($key  eq 'APCP2') {
				#sommo tutto e non non divido
				$tot = $tot_apcp2;
				
			}
			if ($key  eq 'APCP3') {
				#sommo tutto e non non divido
				$tot = $tot_apcp3;
				
			}
			if ($key  eq 'APCP4') {
				#sommo tutto e non non divido
				$tot = $tot_apcp4;
				
			}
			if ($key  eq 'APCP5') {
				#sommo tutto e non non divido
				$tot = $tot_apcp5;
				
			}
			if ($key  eq 'APCP6') {
				#sommo tutto e non non divido
				$tot = $tot_apcp6;
				
			}
			if ($key  eq 'APCP7') {
				#sommo tutto e non non divido
				$tot = $tot_apcp7;
				
			}
			if ($key eq 'PRES') {
				#sommo tutto, fo la media e divido per 100 (hpascal)
				$tot = $tot/$i3/100;
			}
			if ($key eq 'TMP') {
				#sommo tutto, fo la media e sommo 273
				$tot = $tot/$i3-273;
			}
			if ($key eq 'VGRD' || $key eq 'UGRD' || $key eq 'RH') {
				#sommo tutto e la media
				$tot = $tot/$i3;
			}
			$test_i++;
			#print FOUT "$test_i\t$lon\t$lat\t$tot\n";
			my $valbin = pack ('f',$tot);
			print FOUT $valbin;
			
			#creo le coordinate punto punto
			# 			
			if ($lon==$maxlon && $index2>1) {
				$lon = $minlon;
				$lat = $lat-$res; 
			} else {
			#print "lon1: $lon1\n";
				$lon++;
				$lon_i++;
			}
			
			#Massimo e minimo
			#print "$tot\n";
			if ($min_value>$tot) {
				$min_value=$tot;
			}
			if ($max_value<$tot) {
				$max_value=$tot;
			}
			
			#print "lon1: $lon_i \tlon: $lon \t lat: $lat\n";
		}


	}

	chomp($min_value);
	chomp($max_value);

	$self->_debug( "min val ($min_value):: max val ($max_value)");
	#print "test_i ($test_i):: index2 ($index2)\n";

	close(FOUT);#chiudo il file di aggregazione dati
	
	
	
	##NOTA -> LORE -> per output binary
	open(SCRIVI_RDC,">$nome_file_rdc");
	print SCRIVI_RDC "file format : IDRISI Raster A.1\n";
	print SCRIVI_RDC "file title  : $nome_file_out\n";
	print SCRIVI_RDC "data type   : real\n";
	print SCRIVI_RDC "file type   : binary\n";
	print SCRIVI_RDC "columns     : $col\n";
	print SCRIVI_RDC "rows        : $rig\n";
	print SCRIVI_RDC "ref. system : latlong\n";
	print SCRIVI_RDC "ref. units  : deg\n";
	print SCRIVI_RDC "unit dist.  : 1.0000000\n";
	print SCRIVI_RDC "min. X      : $minlon\n";
	#$maxlon=($ncol*$res)+$minlon;
	print SCRIVI_RDC "max. X      : $maxlon\n";
	print SCRIVI_RDC "min. Y      : $minlat\n";
	#$maxlat=($nrig*$res)+$minlat;
	print SCRIVI_RDC "max. Y      : $maxlat\n";
	print SCRIVI_RDC "pos'n error : unknown\n";
	print SCRIVI_RDC "resolution  : $res\n";
	print SCRIVI_RDC "min. value  : $min_value\n";
	print SCRIVI_RDC "max. value  : $max_value\n";
	print SCRIVI_RDC "display min : $min_value\n";
	print SCRIVI_RDC "display max : $max_value\n";
	print SCRIVI_RDC "value units : unknown\n";
	print SCRIVI_RDC "value error : unknown\n";
	print SCRIVI_RDC "flag value  : none\n";
	print SCRIVI_RDC "flag def'n  : none\n";
	print SCRIVI_RDC "legend cats : 0";
	
	#elimanates useless files
	#system("rm temp.txt");
	
	#closes files
	close(SCRIVI_RDC);

}





sub idrisi2png_exe {
	my $self = shift;
	my $key = shift;
	my $value = shift;
# 	my $key = @_[0];
# 	my $value = @_[1];
	
	
# 	  ($fileout, $nrig, $ncol, $minlon, $minlat, $res)=@ARGV;
# 	($key, $value)=@ARGV; 
# 	$nrig = 26;
# 	$ncol = 68;
# 	$minlon=-18;
# 	$minlat = 3;
# 	$res = 1;
	my $nrig = $self->{D_LAT};
	my $ncol = $self->{D_LON};
	
		
	my $minlon= $self->{MINLON};
	my $minlat = $self->{MINLAT};
	my $res = 1;

	my $fileout = $key."_".$value;
	
	

  my $data = $self->forecast_db_date(time);
  my $fra7gg=(time+518400);
  my $data_fra7gg= $self->forecast_db_date($fra7gg);
  my $file_rst = "media_".$fileout."\.rst";
  my $file_png = $fileout."_"."$data"."\.png";
  my $file_ctl = $fileout."_"."$data"."\.ctl";
  my $file_gs = $fileout."_"."$data"."\.gs";
  #$file_gra = $fileout."_"."$data"."_gra"."\.rst";
  my $file_gra = $file_rst;
  
  #
  ##CREA CTL
  open(CTL,">$file_ctl") || die "Non apre file ctl ($file_ctl)\n";
  print CTL "dset ^$file_gra"."\n";
  print CTL "title \"titolo_mancante   Date:"."\n";
  print CTL "OPTIONS yrev"."\n"; #rovescia le Y
  print CTL "Undef -999"."\n"; 
  print CTL "xdef $ncol linear $minlon $res"."\n";
  print CTL "ydef $nrig linear $minlat $res"."\n";
  print CTL "zdef 1 levels 500hpa"."\n";
  print CTL "TDEF 1 LINEAR 00Z1aug1982 10dy"."\n";
  print CTL "vars 1"."\n";
  print CTL "$fileout\t0 99 Trend"."\n"; #qua va messo il nome della variabile da visualizzare
  print CTL "endvars"."\n";
  close(CTL);  
  
  #
  ##CREA GS
  open(OUT,">muletto\.gs") || die "Non apre file $file_gs\n";
  print OUT "'open $file_ctl'\n";
  print OUT "'set mpdset hires'\n";
  if ($fileout=~m/PRES/) {
  	print OUT "'set gxout contour'\n";
  } else {
  	print OUT "'set gxout shaded'\n";
  }
  print OUT "'set grads off'\n";
  print OUT "'set grid off'\n";
  #
  ##PALETTE
  if ($fileout=~m/APCP/) {
  	if ($fileout=~m/hr/) {
  		print OUT "
' set rgb 20 255 255 255' 
' set rgb 21 180 240 250' 
' set rgb 22 120 185 250' 
' set rgb 23 80 165 245' 
' set rgb 24 40 130 240' 
' set rgb 25 30 110 235' 
' set rgb 26 255 232 120' 
' set rgb 27 255 192 60' 
' set rgb 28 255 96 0' 
' set rgb 29 255 50 0' 
' set rgb 30 192 0 0' 
' set rgb 31 165 0 0' 
' set rgb 32 240 220 210' 
' set rgb 33 200 255 190' 
' set rgb 34 150 245 140' 

'set ccols 20 32 33 34 21 22 23 24 25 26 27 28 29 30 31' 
'set clevs 0 1 2 4 6 12 16 20 25 30 40 50 80 100'
";
  	} else {
  		print OUT "
' set rgb 20 255 255 255'
' set rgb 21 180 240 250'
' set rgb 22 120 185 250'
' set rgb 23 80 165 245'
' set rgb 24 40 130 240'
' set rgb 25 30 110 235'
' set rgb 26 255 232 120'
' set rgb 27 255 192 60'
' set rgb 28 255 96 0'
' set rgb 29 255 50 0'
' set rgb 30 192 0 0'
' set rgb 31 165 0 0'
' set rgb 32 240 220 210'
' set rgb 33 200 255 190'
' set rgb 34 150 245 140'

'set ccols 20 32 33 34 21 22 23 24 25 26 27 28 29 30 31'
'set clevs 0 5 10 20 40 80 100 120 150 200 250 300 400'
";
  	}
  }
  if ($fileout=~m/TMP/) {
		print OUT "
*light yellow to dark red 
'set rgb 81 130   0   0' 
'set rgb 82 100   0   0' 
'set rgb 21 255 250 170' 
'set rgb 22 255 232 120' 
'set rgb 23 255 192  60' 
'set rgb 24 255 160   0' 
'set rgb 25 255 115   0' 
'set rgb 26 255  50   0' 
'set rgb 27 225  20   0' 
'set rgb 28 192   0   0' 
'set rgb 29 165   0   0' 

'set ccols 21 22 23 24 25 26 27 28 29'
'set clevs 24 26 27 28 29 30 32 34'
"; 
  }
  if ($fileout=~m/RH/) {
  	print OUT "
' set rgb 20 255 232 120'
' set rgb 21 255 250 170'
' set rgb 22 230 255 225'
' set rgb 23 200 255 190'
' set rgb 24 180 250 170'
' set rgb 25 150 210 250'
' set rgb 26 120 185 250'
' set rgb 27 80 165 245'
' set rgb 28 160 140 255'
' set rgb 29 128 112 235'
' set rgb 30 72 60 200'

'set ccols 20 21 22 23 24 25 26 27 28 29 30'
'set clevs 10 20 30 40 50 60 70 80 90'
";  
  }
  #
  ##DISPLAY VARIABLE

  print OUT "'display $fileout'\n";
  
if ($self->{CBARN_PATH}) {
	print OUT "'run ".$self->{CBARN_PATH}."'\n"; 
}

	
  ##TITLE
  my $subtitle = undef;
  
  if ($fileout=~m/1000/) {
  	$subtitle='Level 1000 mb -';
  } elsif ($fileout=~m/925/) {
  	$subtitle='Level 925 mb -';
  } elsif ($fileout=~m/850/) {
  	$subtitle='Level 850 mb -';
  } else {
  	$subtitle='Level Surface -';
  }
  #################VALIDITA' PREVISIONE#################
  my $previ = $fileout;
  $previ =~s /APCP_//g;  
  if ($fileout=~m/APCP_/) {
  	$subtitle="$subtitle"." Forecast $data 00Z+ $previ";
  } else {
  	$subtitle="$subtitle"." Forecast $data 00Z valid until $data_fra7gg";
  }
  #################VALIDITA' PREVISIONE#################  
  if ($fileout=~m/APCP/) {
  	print OUT "'draw title TOTAL PRECIPITATION [mm]\\$subtitle'\n";  	
  } elsif ($fileout=~m/RH/) {
	print OUT "'draw title RELATIVE HUMIDITY [%]\\$subtitle'\n";
  } elsif ($fileout=~m/TMP/) {
	print OUT "'draw title TEMPERATURE [C]\\$subtitle'\n";
  } elsif ($fileout=~m/PRES/) {
	print OUT "'draw title PRESSURE [mb]\\$subtitle'\n";
  } elsif ($fileout=~m/UGRD/) {
	print OUT "'draw title ZONAL WIND [m/s]\\$subtitle'\n";
  } elsif ($fileout=~m/VGRD/) {
	print OUT "'draw title MERIDIONAL WIND [m/s]\\$subtitle'\n";
  }
  #
  ##SCRITTE VARIE
  print OUT "'set strsiz 0.15'\n";
  if ($fileout=~m/APCP/) {
  	print OUT "'draw string 5.5 1.5 Unit [mm]'\n";  	
  } elsif ($fileout=~m/RH/) {
	print OUT "'draw string 5.5 1.5 Unit [%]'\n";
  } elsif ($fileout=~m/TMP/) {
	print OUT "'draw string 5.5 1.5 Unit [C]'\n";
  } elsif (($fileout=~m/UGRD/) || ($fileout=~m/VGRD/)) {
	print OUT "'draw string 5.5 1.5 Unit [m/s]'\n";
  } elsif ($fileout=~m/PRES/) {
	print OUT "'draw string 5.5 1.5 Unit [mb]'\n";
  }
  if (($fileout=~m/TMP/) || ($fileout=~m/VGRD/) || ($fileout=~m/UGRD/) || ($fileout=~m/RH/)) {
	print OUT "'set gxout contour'\n";
	print OUT "'display $fileout'\n";
  }
  #
  ##SAVES PNG & QUIT
#   print OUT "'printim $curdir\\$file_png x800 y600 white'\n";
  print OUT "'printim $file_png x800 y600 white'\n";

  
  #print OUT "'clear'\n";
  print OUT "'quit'\n";
#   print OUT " return\n";
  close(OUT);
  
  ## 
  system($self->{GRADSC_PATH}." -blc muletto\.gs");
 # print "idrisi2png conpleted\n";
}

#########################################################################
#
#	STATIC methods go here
#
#------------------------------------------------------------------------
sub is_integer {
	my $self = shift;
	my $value = shift;
	if ("".$value =~ /[-+]?[0-9]*[^a-z\.]/ ) {
		$self->_debug("Value is: ".$value);
		return 1;
		}
	else {
		$self->_debug("Value is: null ");
		return 0;
	}
}

 
sub absolute_integer_value {
	my $self = shift;
	my $value = shift;
	#$self->_debug("Value in: ".$value);
	
	#elimino qualsiasi decimale. 
	$value =~ s/([1-9]*)[\.\,][1-9]+/$1/g;

	#tolgo tutti i caratteri AlfaBetici, punti e virgole
	$value =~ s/[A-Za-z-+\.\,]//g;
	
	#$self->_debug("Value out: ".$value);
	
	return $value;
}  


	
sub data_formattata_forecast {
        #questa subroutine si aspetta la funzione "time"
        #in entrata oppure un'altro valure di data similare
        my $self = shift;
        my $adesso = shift;
        my ($sec,$min,$hour,$mday,$mon,$year)=localtime($adesso);
        
        $sec = $self->number_format_00($sec);
        $min = $self->number_format_00($min);
        $hour = $self->number_format_00($hour);
        $mday = $self->number_format_00($mday);
        $mon = $self->number_format_00($mon+1);
        $year = $self->number_format_00($year);
        
        return "$mday/$mon/$year - $hour:$min:$sec";
}

	
sub forecast_db_date {
        #questa subroutine si aspetta la funzione "time"
        #in entrata oppure un'altro valure di data similare
        my $self = shift;
        my $adesso = shift;
        my ($sec,$min,$hour,$mday,$mon,$year)=localtime($adesso);
        
        $sec = $self->number_format_00($sec);
        $min = $self->number_format_00($min);
        $hour = $self->number_format_00($hour);
        $mday = $self->number_format_00($mday);
        $mon = $self->number_format_00($mon+1);
        $year = $self->number_format_00($year);
        
        return "$mday$mon$year";
}


sub number_format_00 {
	my $self = shift;
        my $num = shift;
        my $len = length($num);
        #print $len;
        if($len > 2){
                my $inizio = $len - 2;
                $num = substr($num,$inizio);
        }
        if($len <2){
                $num = "0".$num;
        }
        return $num;
}




1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Weather::NOAA::GFS - Perl extension for forecast climate maps from NOAA GFS site

=head1 SYNOPSIS

  use Weather::NOAA::GFS;

  
  # define parameters 
    my %params = (
		'minlon'   => -5,# mandatory
		'maxlon'   => 45,# mandatory
		'minlat'   => 30,# mandatory
		'maxlat'   => 50,# mandatory
		'mail_anonymous'    => 'my@mail.org',# mandatory to log NOAA ftp server
		'gradsc_path' => 'gradsc',# mandatory, needed to create maps
		'wgrib_path' => 'wgrib',# mandatory, needed to process NOAA GRIB files
		'debug'    => 1, # 0 no output - 1 output
		'logfile'    => 'weather-noaa-gfs.log',# optional
		'cbarn_path' => 'cbarn.gs', #optional, needed to print image legend
		'r_path' => 'R',# optional, needed to downscale
		
  );
  
  
  # instantiate a new NOAA::GFS object
  my $weather_gfs = Weather::NOAA::GFS->new(%params);
  
  #download Grib files for your area

  if($weather_gfs->downloadGribFiles()){
  	print "downloadGribFiles done!!!";
  } else {
  	print "Error: downloadGribFiles had problems!!!";
	die;
  }
  
  #transform Grib files to Ascii files (needs GrADS's wgrib)
  
  if($weather_gfs->grib2ascii()){
  	print "grib2ascii succeded!!!";
  } else {
  	print "Error: grib2ascii had problems!!!";
	die;
  }

  #transform Ascii files to IDRISI files
  
  if($weather_gfs->ascii2idrisi()){
  	print "ascii2idrisi succeded!!!";
  } else {
  	print "Error: ascii2idrisi had problems!!!";
	die;
  }

  
  #itransform Idrisi files to Png images (needs GrADS's gradsc)
  if($weather_gfs->idrisi2png()){
  	print "idrisi2png succeded!!!";
  } else {
  	print "Error: idrisi2png had problems!!!";
	die;
  }

=head1 DESCRIPTION


This module produces forecast climate maps from NOAA GFS site (http://nomad2.ncep.noaa.gov/ncep_data/). It
 downloads rough data, transforms it into IDRISI (binary GIS format) and then
     in PNG maps. Output maps are for temperature, relative humidity,
     zonal wind, pressure and rainfall precipitation. The module requires
     some extra software installed: GrADS (mandatory)
    (http://grads.iges.org/grads/grads.html) to create PNG output and R
    (optional) (http://www.r-project.org/) to downscale the 1 degree
     resolution to 0.1 degree.
     

=head1 TO DO

1) integration with R
2) better image output


=head1 SEE ALSO

Software needed:

GrADS - http://grads.iges.org/grads/grads.html
used: wgrib, gradsc. Need cbarn.gs

R - http://www.r-project.org/
add module GStat


=head1 AUTHORS

Alfonso Crisci, E<lt>crisci@ibimet.cnr.itE<gt>
Valerio Capecchi, E<lt>capecchi@ibimet.cnr.itE<gt>
Lorenzo Becchi, E<lt>lorenzo@ominiverdi.comE<gt>


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2004 by Lorenzo Becchi

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.5 or,
at your option, any later version of Perl 5 you may have available.


=cut
