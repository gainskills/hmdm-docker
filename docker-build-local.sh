docker build \
  --build-arg CLIENT_VERSION=6.36 \
  --build-arg HMDM_URL=https://h-mdm.com/files/hmdm-java21-5.39.2.1-os.war \
  -t hanbaobao2005/hmdm:java21-260619 .