class openstack_tasks::roles::allocate_hugepages {

  notice('MODULAR: roles/allocate_hugepages.pp')

  $hugepages = hiera('hugepages', [])

  include ::sysfs

  sysfs_config_value { 'hugepages':
    ensure => 'present',
    name   => '/etc/sysfs.d/hugepages.conf',
    value  => map_sysfs_hugepages($hugepages),
    sysfs  => '/sys/devices/system/node/node*/hugepages/hugepages-*kB/nr_hugepages',
    # TODO: (vvalyavskiy) should be wiped out as soon as kernel will be upgraded to 3.16 version
    exclude => '/sys/devices/system/node/node*/hugepages/hugepages-1048576kB/nr_hugepages',
  }

  # LP 1507921
  sysctl::value { 'vm.max_map_count':
    value  => max_map_count_hugepages($hugepages),
  }

}