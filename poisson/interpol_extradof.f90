#ifndef OLDINTERP





subroutine interpol_extradof(ind_cell,sf_int,ncell,ilevel,icount)
  use amr_commons
  use extradof_commons, only:sf,sf_old
  implicit none
  integer::ncell,ilevel,icount
  integer ,dimension(1:nvector)::ind_cell
  real(dp),dimension(1:nvector,1:twotondim)::sf_int
 
  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  ! Routine for interpolation at level-boundaries. Interpolation is used for
  ! - boundary conditions for solving poisson equation at fine level
  ! - computing force (gradient_extradof) at fine level for cells close to boundary
  ! Interpolation is performed in space (CIC) and - if adaptive timestepping is on -
  ! time (linear extrapolation of the change in sf during the last coarse step 
  ! onto the first fine step)
  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  
  integer ,dimension(1:nvector,1:twotondim),save::nbors_father_grids
  integer ,dimension(1:nvector,1:threetondim),save::nbors_father_cells
  integer::i,ind,indice,ind_average,ind_father
  real(dp)::dx,tfrac



  real(dp)::aa,bb,cc,dd,coeff,add
  integer,dimension(1:8,1:8)::ccc
  real(dp),dimension(1:8)::bbbb

  ! CIC method constants
  aa = 1.0D0/4.0D0**ndim
  bb = 3.0D0*aa
  cc = 9.0D0*aa
  dd = 27.D0*aa
  bbbb(:)  =(/aa ,bb ,bb ,cc ,bb ,cc ,cc ,dd/)

  !sampling positions in the 3x3x3 father cell cube
  ccc(:,1)=(/1 ,2 ,4 ,5 ,10,11,13,14/)
  ccc(:,2)=(/3 ,2 ,6 ,5 ,12,11,15,14/)
  ccc(:,3)=(/7 ,8 ,4 ,5 ,16,17,13,14/)
  ccc(:,4)=(/9 ,8 ,6 ,5 ,18,17,15,14/)
  ccc(:,5)=(/19,20,22,23,10,11,13,14/)
  ccc(:,6)=(/21,20,24,23,12,11,15,14/)
  ccc(:,7)=(/25,26,22,23,16,17,13,14/)
  ccc(:,8)=(/27,26,24,23,18,17,15,14/)

  if (icount .ne. 1 .and. icount .ne. 2)then
     write(*,*), 'icount has bad value'
     call clean_stop
  endif

  !compute fraction of timesteps for interpolation
  if (dtold(ilevel-1)> 0)then
     !tfrac=0.
     tfrac=1.0*dtnew(ilevel)/dtold(ilevel-1)*(icount-1)
  else
     tfrac=0.
  end if

  ! Mesh size at level ilevel
  dx=0.5D0**ilevel
  call get3cubefather(ind_cell,nbors_father_cells,nbors_father_grids,ncell,ilevel)

  ! Third order extradof interpolation
  do ind=1,twotondim
     do i=1,ncell
        sf_int(i,ind)=0d0
     end do
     do ind_average=1,twotondim
        ind_father=ccc(ind_average,ind)
        coeff=bbbb(ind_average)
        do i=1,ncell
           indice=nbors_father_cells(i,ind_father)
           if (indice==0) then 
              write(*,*),'no all neighbors present in interpol_extradof..'
              add=coeff*(sf(ind_cell(i))+(sf(ind_cell(i))-sf_old(ind_cell(i)))*tfrac)
           else
              add=coeff*(sf(indice)+(sf(indice)-sf_old(indice))*tfrac)
           endif
           sf_int(i,ind)=sf_int(i,ind)+add
        end do
     end do
  end do

 end subroutine interpol_extradof
!###########################################################
!###########################################################
!###########################################################
!###########################################################
subroutine save_extradof_old(ilevel)
  use amr_commons
  use extradof_commons, only:sf,sf_old
  implicit none
  integer ilevel

  !save the old extradof for time extrapolation in case of subcycling

  integer::i,ncache,ind,igrid,iskip,istart,ibound
  integer,allocatable,dimension(:)::ind_grid

  do ibound=1,nboundary+ncpu
     if(ibound<=ncpu)then
        ncache=numbl(ibound,ilevel)
        istart=headl(ibound,ilevel)
     else
        ncache=numbb(ibound-ncpu,ilevel)
        istart=headb(ibound-ncpu,ilevel)
     end if
     if(ncache>0)then
        allocate(ind_grid(1:ncache))
        ! Loop over level grids
        igrid=istart
        do i=1,ncache
           ind_grid(i)=igrid
           igrid=next(igrid)
        end do
        ! Loop over cells
        do ind=1,twotondim
           iskip=ncoarse+(ind-1)*ngridmax
           ! save extradof
           do i=1,ncache
              sf_old(ind_grid(i)+iskip)=sf(ind_grid(i)+iskip)
           end do
        end do
        deallocate(ind_grid)
     end if
  end do

end subroutine save_extradof_old




#else




subroutine interpol_extradof(ind_cell,sf_int,ncell,ilevel,icount)
  use amr_commons
  use extradof_commons
  use extradof_parameters

  implicit none

  integer :: ncell,ilevel,icount
  integer,dimension(1:nvector) :: ind_cell
  real(dp),dimension(1:nvector,1:twotondim) :: sf_int

  integer  :: i,idim,ind,ix,iy,iz
  real(dp) :: dx
  real(dp),dimension(1:twotondim,1:3),save  :: xcc
  real(dp),dimension(1:nvector),save        :: aa
  real(dp),dimension(1:nvector,1:ndim),save :: ww

  ! Mesh size at level ilevel
  dx=0.5D0**ilevel

  ! Set position of cell centers relative to grid center
  do ind=1,twotondim
     iz=(ind-1)/4
     iy=(ind-1-4*iz)/2
     ix=(ind-1-2*iy-4*iz)
     if(ndim>0) xcc(ind,1) = (dble(ix)-0.5D0)*dx
     if(ndim>1) xcc(ind,2) = (dble(iy)-0.5D0)*dx
     if(ndim>2) xcc(ind,3) = (dble(iz)-0.5D0)*dx
  end do

  ! Gather father sf
  do i=1,ncell
     aa(i) = sf(ind_cell(i))
  end do

  ! Gather father (minus) 3-derivative of sf
  do idim=1,ndim
     do i=1,ncell
        ww(i,idim) = -sf_grad(ind_cell(i),idim)
     end do
  end do

  ! Interpolate
  do ind=1,twotondim
#if NDIM==1
     do i=1,ncell
        sf_int(i,ind) = aa(i)+ww(i,1)*xcc(ind,1)
     end do
#endif
#if NDIM==2
     do i=1,ncell
        sf_int(i,ind) = aa(i)+ww(i,1)*xcc(ind,1)+ww(i,2)*xcc(ind,2)
     end do
#endif
#if NDIM==3
     do i=1,ncell
        sf_int(i,ind) = aa(i)+ww(i,1)*xcc(ind,1)+ww(i,2)*xcc(ind,2)+ww(i,3)*xcc(ind,3)
     end do
#endif
  end do

end subroutine interpol_extradof




#endif
