#!/bin/sh
#SBATCH --time=96:00:00
#SBATCH --signal=B:SIGUSR1@300    
#SBATCH --ntasks=30
#SBATCH --nodes=1
#SBATCH --mem=92000
#SBATCH --output=rstudio_summer_school_login.txt
#SBATCH --error=rstudio_summer_school_errors.txt
#SBATCH --job-name=ngscnsummerschool
#SBATCH --partition=ngscourse.q

# EDIT: PORT (line 27)

###################################                       
# USER-SPECIFIC SETTINGS (CHANGE) #
###################################
                    
# Set the user login (needs to be the same as above in output, error and job-name
USER=$(whoami)

# Set a generic password
PASSWORD=$(openssl rand -base64 8)

# Set a port between 9000 and 9025
PORT=9002

# Set path/url to Singularity image
SINGULARITY_IMAGE=oras://gcr.hrz.tu-chemnitz.de/dcgc-bfx/singularity/singularity-single-cell:Unstable

########################################################################
# COPIED/ADAPTED FROM: https://rocker-project.org/use/singularity.html #
########################################################################

# Fail when error
set -ef -o pipefail

# Create a unique temporary directory for this job
workdir=$(mktemp -p /tmp  -d summer_school.XXXXXXXXXX)

# 300s before end of the job, slurm sends the signal SIGUSR1. If a job is canceled, slurm sends the signal SIGTERM. 
# Intercept these signals, then run this function to shut down the job gracefully.
function shutdown()
{
	# Undo trap
	trap " " SIGUSR1 SIGTERM

	# Terminate all child processes
	kill 0

	# Wait until done
	wait

	# Remove working directory
	rm -rf "${workdir}"
}

# associate the function "sig_handler_USR1" with the USR1 signal
trap 'shutdown' SIGUSR1 SIGTERM

# This is the working directory for singularity
mkdir ${workdir}/singularity

# This is the working directory for the R server
mkdir ${workdir}/rserver

# This is the temp directory for computations in R
mkdir ${workdir}/tmp

# Host name
COMPUTE_NODE=$(hostname | sed 's/.biocluster$//')

# Print message with instructions
cat <<END
########################################
# How to connect to the RStudio Server #
########################################

1. Create an SSH tunnel from your laptop to our cluster head node:

- In Linux/Mac, open a terminal. In Windows, open the "Windows PowerShell". Then type in:
   ssh -N -L ${PORT}:localhost:${PORT} ${USER}@biocluster4

- When asked about the "The authenticity of host ...", type "yes" to connect.

2. Open your web browser (preferably Chrome or Firefox) and point it to: http://localhost:${PORT}

3. Log into RStudio Server using the following credentials:

   user: ${USER}
   password: ${PASSWORD}

#############################################
# How to disconnect from the RStudio Server #
#############################################

1. You can disconnect from the RStudio Server by closing the ssh tool or shell. After that you can even close your laptop. 
2. Your RStudio will continue running on our cluster until the job is terminated at the end of the workshop.
3. To reconnect, follow the steps "How to connect to the RStudio Server" again.

#######################################
# How to terminate the RStudio Server #
#######################################

1. Exit the RStudio Session ("power" button in the top right corner of the RStudio window)
2. Issue the following command on the login node:

      scancel ${SLURM_JOB_ID}
END

# Load singularity and set variables that should be exported from host environment
module load apps/singularity

export SINGULARITYENV_RSTUDIO_USER=${USER}
export SINGULARITYENV_RSTUDIO_PASSWORD=${PASSWORD}
export SINGULARITYENV_RSTUDIO_PORT=${PORT}
export SINGULARITYENV_RSTUDIO_SESSION_TIMEOUT=0

# Start R-Server
singularity exec \
  --cleanenv \
  --scratch /run,/var/lib/rstudio-server \
  --workdir ${workdir}/singularity \
  --bind ${workdir}/tmp \
  --bind ${workdir}/rserver \
  ${SINGULARITY_IMAGE} \
  micromamba run --name single-cell /usr/lib/rstudio-server/bin/rserver --server-user=${USER} --www-port=${PORT} &

#  Tunnel back to biocluster4 with ssh
ssh -o ServerAliveInterval=300 -N -R ${PORT}:localhost:${PORT} biocluster4

printf 'rserver exited'
