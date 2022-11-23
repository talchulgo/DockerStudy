#################### Configuration Begin ##############################

# Base Container Image
FROM nvidia/cuda:11.4.2-cudnn8-devel-centos8

# Anaconda & Python version config
ARG ANACONDA_VERSION=2022.05
#ARG PYTHON_VERSION=3.7

# Tensorflow version config - comment below if you don't want to install tensorflow
ARG TENSORFLOW_VERSION=2.9.1
#ARG TENSORFLOW_VERSION=2.8.2

# Pytorch version config - comment below if you don't want to install pytorch
ARG PYTORCH_VERSION=1.11.0

#################### Configuration End ##############################

LABEL maintainer="CloudHUB <support@brickcloud.co.kr>"

ARG NB_USER="posco"
ARG NB_UID="1000"
ARG NB_GID="100"

# Fix DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root

# Install OS dependencies
RUN sed -i -e 's/mirrorlist/#mirrorlist/g' -e 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-Linux-* && \
    yum install -y bzip2 wget sudo ca-certificates && \
    #yum update -y && \
    yum clean all && rm -rf /var/cache/yum/* /tmp/* /root/.cache

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
    HOME=/home/$NB_USER
ENV TZ=Asia/Seoul

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone

# Copy a permission script
COPY fix-permissions /usr/local/bin/fix-permissions
RUN chmod a+rx /usr/local/bin/fix-permissions

# Enable prompt color in the skeleton .bashrc before creating the default NB_USER
RUN sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /etc/skel/.bashrc

# Create NB_USER
RUN echo "auth requisite pam_deny.so" >> /etc/pam.d/su && \
    sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
    useradd -m -s /bin/bash -N -u $NB_UID $NB_USER && \
    mkdir -p $CONDA_DIR && \
    chown $NB_USER:$NB_GID $CONDA_DIR && \
    chmod g+w /etc/passwd && \
    fix-permissions $HOME && \
    fix-permissions $CONDA_DIR

USER $NB_UID
WORKDIR $HOME

# Setup work directory for backward-compatibility
RUN mkdir /home/$NB_USER/work && \
    fix-permissions /home/$NB_USER

ENV CONDA_VERSION=4.12.0

# Install Anaconda
WORKDIR /tmp

RUN curl -k -o /tmp/Anaconda3-${ANACONDA_VERSION}-Linux-x86_64.sh https://repo.anaconda.com/archive/Anaconda3-${ANACONDA_VERSION}-Linux-x86_64.sh  && \
    /bin/bash Anaconda3-${ANACONDA_VERSION}-Linux-x86_64.sh -f -b -p $CONDA_DIR && \
    rm Anaconda3-${ANACONDA_VERSION}-Linux-x86_64.sh && \
    echo "conda ${CONDDA_VERSON}" >> $CONDA_DIR/conda-meta/pinned && \
    conda config --set ssl_verify false && \
    conda config --system --prepend channels conda-forge && \
    conda config --system --set auto_update_conda false && \
    conda config --system --set show_channel_urls true && \
    conda config --system --set channel_priority flexible && \
    #conda config --system --set channel_priority strict && \
    if $PYTHON_VERSION; then conda install --quiet --yes python=$PYTHON_VERSION; fi && \
    conda list python | grep '^python ' | tr -s ' ' | cut -d '.' -f 1,2 | sed 's/$/.*/' >> $CONDA_DIR/conda-meta/pinned && \
    #conda install --update-deps --quiet --yes conda && \
    conda install --quiet --yes conda && \
    conda install --quiet --yes pip && \
    #pip install --upgrade --no-cache-dir pip && \
    conda update --all --quiet --yes && \
    conda clean --all -f -y && \
    rm -rf /home/$NB_USER/.cache && \
    fix-permissions $CONDA_DIR && \
    fix-permissions /home/$NB_USER

# Install Tini
RUN conda config --set ssl_verify false && \
    conda install --quiet --yes 'tini=0.18.0' && \
    conda list tini | grep tini | tr -s ' ' | cut -d ' ' -f 1,2 >> $CONDA_DIR/conda-meta/pinned && \
    conda clean --all -f -y  && \
    fix-permissions $CONDA_DIR && \
    fix-permissions /home/$NB_USER

# Install Tensorflow
RUN conda config --set ssl_verify false && \
    conda install --quiet --yes tensorflow=$TENSORFLOW_VERSION && \
    conda clean --yes --all && \
    fix-permissions $CONDA_DIR && \
    fix-permissions /home/$NB_USER;

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
