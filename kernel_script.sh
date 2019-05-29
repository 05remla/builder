echo "1. clear directory for new build"
echo "2. extract and prepare"
echo "3. compile"
echo
echo "[1-3]: "
read option

cd /root/BUILD/
if [[ $option == 1 ]]; then
  for i in $(ls)
  do
    if [[ -d ${i} ]]; then
      rm -rf ${i}
    elif [[ ${i} == *".deb" ]]; then
      rm -rf ${i}
    elif [[ ${i} == *".changes" ]]; then
      rm -rf ${i}
    elif [[ ${i} == *".buildinfo" ]]; then
      rm -rf ${i}
    elif [[ ${i} == "linux" ]]; then
      rm -rf ${i}
    fi
  done

elif [[ $option == 2 ]]; then
  tar -xvf *.tar.gz
  ln -s linux* linux
  cd linux
  make clean && make mrproper
  echo "path to config file?"
  printf "> "
  read configfile
  cp $configfile ./.config

elif [[ $option == 3 ]]; then
  make -j7 bindeb-pkg
fi
