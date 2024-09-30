#################### Configuration Begin ##############################
## 24.09.30 Modify ##

# Base Container Image
#FROM nvidia/cuda:11.4.2-cudnn8-devel-centos8
FROM ubuntu:22.04

LABEL maintainer="P)EIC teck Part <kohs8208@posco.com>"

ARG NB_USER="posco"
ARG NB_UID="10000"
ARG NB_GID="10000"

# Fix DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root

# install all OS dependencies for notebook server that starts but lacks all
# features (e.g., download as all possible file formats)
ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && \
    apt-get install -yq --no-install-recommends \
    apt-utils \
    build-essential \
    tini \
    wget \
    bzip2 \
    ca-certificates \
    vim \
    curl \
    net-tools \
    gettext \
    unzip \
    supervisor \
    openssh-server \
    gnupg \
    git \
    sudo \
    locales \
    fonts-liberation \
    pandoc \
    run-one && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Graphic Library & Database Client
RUN apt-get update && \
    apt-get install -yq \
    libgl1-mesa-dev \
    libglu1-mesa-dev \
    mariadb-client \
    postgresql-client \
    fonts-nanum fonts-nanum-coding fonts-nanum-extra && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Configure Container Environment
ENV CONDA_DIR=/opt/conda \
    SHELL=/bin/bash \
    NB_USER=$NB_USER \
    NB_UID=$NB_UID \
    NB_GID=$NB_GID \
    LC_ALL=en_US.UTF8 \
    LANG=en_US.UTF8 \
    LANGUAGE=en_US.UTF8 \
    PIP_USE_FEATURE=2020-resolver
ENV PATH=$CONDA_DIR/bin:$PATH \
    TZ=Asia/Seoul

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone

# Copy a permission script
COPY fix-permissions /usr/local/bin/fix-permissions
RUN chmod a+rx /usr/local/bin/fix-permissions

# Enable prompt color in the skeleton .bashrc before creating the default NB_USER
RUN sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /etc/skel/.bashrc

# Create NB_USER with name posco user with UID=10000
RUN echo "auth requisite pam_deny.so" >> /etc/pam.d/su && \
    sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
    groupadd -g $NB_GID $NB_USER && \
    useradd -m -s /bin/bash -N -u $NB_UID $NB_USER && \
    echo "%$NB_USER ALL=NOPASSWD: ALL" >> /etc/sudoers && \
    mkdir -p /home/user && \
    mkdir -p $CONDA_DIR && \
    chown $NB_USER:$NB_GID $CONDA_DIR && \
    chmod g+w /etc/passwd && \
    fix-permissions /home/$NB_USER && \
    fix-permissions $CONDA_DIR

USER $NB_UID
ARG PYTHON_VERSION=default

ENV MINICONDA_VERSION=23.5.2-0 \
    CONDA_VERSION=22.5.2-0

WORKDIR /tmp

# Install Miniconda
RUN wget --quiest https://repo.anaconda.com/miniconda/Miniconda3-py310 ${MINICONDA_VERSION}-Linux-x86_64.sh && \
    /bin/bash Miniconda3-py310_${MINICONDA_VERSION}-Linux-x86_64.sh -f -b -p $CONDA_DIR && \
    rm -f Miniconda3-${CONDA_VERSION}-Linux-x86_64.sh && \
    conda config --set ssl_verify false && \
    conda config --system --prepend channels conda-forge && \
    conda config --system --set auto_update_conda false && \
    conda config --system --set show_channel_urls true && \
    conda config --system --set channel_priority flexible && \
    if [ !$PYTHON_VERSION = 'default']; then conda install --yes python=$PYTHON_VERSION; fi && \
    conda list python | grep '^python ' | tr -s ' ' | cut -d '.' -f 1,2 | sed 's/$/.*/' >> $CONDA_DIR/conda-meta/pinned && \
    conda install --quiet --yes conda && \
    conda install --quiet --yes pip && \
    conda update --all --quiet --yes && \
    conda clean --all -f -y && \
    rm -rf /home/$NB_USER/.cache && \
    fix-permissions $CONDA_DIR && \
    fix-permissions /home/$NB_USER

# Install Jupyter
RUN conda install --quiet --yes \
    notebook \
    jupyterhub \
    jupyterlab \
    ipywidgets && \
    conda clean --all -f -y  && \
    npm cache clean --force && \
    rm -rf $CONDA_DIR/share/jupyter/lab/staging && \
    rm -rf /home/$NB_USER/.cache && \
    fix-permissions $CONDA_DIR && \
    fix-permissions /home/$NB_USER

# Install Tensorflow
#RUN conda config --set ssl_verify false && \
#    conda install --quiet --yes tensorflow=$TENSORFLOW_VERSION && \
#    conda clean --yes --all && \
#    fix-permissions $CONDA_DIR && \
#    fix-permissions /home/$NB_USER;

# Install Pytorch
RUN conda config --set ssl_verify false && \
    conda install --quiet --yes pytorch=$PYTORCH_VERSION torchvision cudatoolkit -c pytorch -c conda-forge && \
    conda clean --yes --all && \
    fix-permissions $CONDA_DIR && \
    fix-permissions /home/$NB_USER;

# Install Other Libraries with conda
RUN conda config --set ssl_verify false && \
    conda install --quiet --yes \
    xgboost=1.6.1 \
    lightgbm=3.3.2 \
    optuna=2.10.1 \
    bayesian-optimization=1.2.0 \
    shap=0.41.0 \
 && conda clean --yes --all && \
    fix-permissions $CONDA_DIR && \
    fix-permissions /home/$NB_USER

# Install Other Libraries with pip : 22.11.18 add -> pymssql , PyMySQL
RUN pip install --no-cache-dir \
    ray==1.13.0 \
    pymssql==2.1.5 \
    PyMySQL==1.0.2 \
 && fix-permissions $CONDA_DIR && \
    fix-permissions /home/$NB_USER

# IPython Passwd Patch(BUG?)
RUN pip uninstall -y --quiet ipython \
 && pip install --no-cache-dir 'ipython>=7,<8' \
 && fix-permissions $CONDA_DIR && \
    fix-permissions /home/$NB_USER

# Configure Jupyter
RUN conda config --set ssl_verify false && \
    conda clean --yes --all && \
    jupyter notebook --generate-config && \
    rm -rf $CONDA_DIR/share/jupyter/lab/staging && \
    rm -rf /home/$NB_USER/.cache/yarn && \
    fix-permissions $CONDA_DIR && \
    fix-permissions /home/$NB_USER


EXPOSE 8888

# Configure container startup
ENTRYPOINT ["tini", "-g", "--"]
CMD ["start-notebook.sh"]

# Copy local files as late as possible to avoid cache busting
COPY start.sh start-notebook.sh start-singleuser.sh /usr/local/bin/
COPY jupyter_notebook_config.py /etc/jupyter/

# Fix permissions on /etc/jupyter as root
USER root
RUN fix-permissions /etc/jupyter/

USER $NB_USER
ADD --chown=1000:100 test $HOME/test

WORKDIR $HOME
