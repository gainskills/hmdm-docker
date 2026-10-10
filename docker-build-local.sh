docker build --no-cache \
  --build-arg CLIENT_VERSION=6.39 \
  --build-arg HMDM_URL=https://h-mdm.com/files/hmdm-java21-5.41.1-os.war \
  -t hanbaobao2005/hmdm:java21-261010 .