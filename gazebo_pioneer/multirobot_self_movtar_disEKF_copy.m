function multirobot_self_movtar_disEKF(~,~)


global N omega_max tarx_hat tary_hat i_store iself_count self_tolerance...
    gVimid id Sigma_hat timer_cnt pose_x_store pose_y_store

[tarx_hat tary_hat]
robot_0_pub_vel = rospublisher('/robot_0/cmd_vel');
robot_1_pub_vel = rospublisher('/robot_1/cmd_vel');
robot_2_pub_vel = rospublisher('/robot_2/cmd_vel');
robot_pub_vel=[robot_0_pub_vel;robot_1_pub_vel;robot_2_pub_vel];
robot_pub_msg = rosmessage('geometry_msgs/Twist');
% publish target vel_cmd
target_pub_vel = rospublisher('/robot_3/cmd_vel');
target_pub_msg = rosmessage('geometry_msgs/Twist');


%subscribe the pose topic to get the positon if the robot
posesub_0 = rossubscriber('/robot_0/pose');
robot0_pose = receive(posesub_0,3);
posesub_1 = rossubscriber('/robot_1/pose');
robot1_pose = receive(posesub_1,3);
posesub_2 = rossubscriber('/robot_2/pose');
robot2_pose = receive(posesub_2,3);
%subscribe target pose
% posesub_tar = rossubscriber('/robot_3/pose');
% target_pose = receive(posesub_tar,3);

%transform the quaternion to the roll, pitch, yaw%[robot0_roll, robot0_pitch, robot0_yaw]
[~, ~, robot0_yaw] = quattoangle([robot0_pose.Orientation.W robot0_pose.Orientation.X robot0_pose.Orientation.Y robot0_pose.Orientation.Z]);
[~, ~, robot1_yaw] = quattoangle([robot1_pose.Orientation.W robot1_pose.Orientation.X robot1_pose.Orientation.Y robot1_pose.Orientation.Z]);
[~, ~, robot2_yaw] = quattoangle([robot2_pose.Orientation.W robot2_pose.Orientation.X robot2_pose.Orientation.Y robot2_pose.Orientation.Z]);


%collect the planar position and orientation (yaw) of the robot
robot0_pose_last=[robot0_pose.Position.X, robot0_pose.Position.Y, robot0_yaw];
robot1_pose_last=[robot1_pose.Position.X, robot1_pose.Position.Y, robot1_yaw];
robot2_pose_last=[robot2_pose.Position.X, robot2_pose.Position.Y, robot2_yaw];

robot_pose_last=[robot0_pose_last;robot1_pose_last;robot2_pose_last];
robot_pose_px=robot_pose_last(:,1);
%to enlarge the position x
robot_pose_px_enl=[robot_pose_px(N,1);robot_pose_px;robot_pose_px(1,1)];


robot_pose_py=robot_pose_last(:,2);
%to enlarge the position y
robot_pose_py_enl=[robot_pose_py(N,1);robot_pose_py;robot_pose_py(1,1)];

%transfrom the positon to the angular
robot0_theta=positiontoangularfun((robot0_pose_last(2)-tary_hat(1)),(robot0_pose_last(1)-tarx_hat(1)));
robot1_theta=positiontoangularfun((robot1_pose_last(2)-tary_hat(2)),(robot1_pose_last(1)-tarx_hat(2)));
robot2_theta=positiontoangularfun((robot2_pose_last(2)-tary_hat(3)),(robot2_pose_last(1)-tarx_hat(3)));

robot_itheta_last=[robot0_theta;robot1_theta;robot2_theta];
robot_itheta_last=orderlythetafun(robot_itheta_last);
%[robot_itheta_last(3)-robot_itheta_last(2),robot_itheta_last(2)-robot_itheta_last(1)]


%collect the data in compact form
robot_theta_last=[(robot_itheta_last(3)-2*pi);robot_itheta_last;(robot_itheta_last(1)+2*pi)]; %virtual agent 0th:=agent N-2pi;virtual agent 7th:=agent 1st+ 2pi

%define the id of all  the robots
for i=1:N
     id(i)=i;
end

%to enlarge label
idb=[N;id(:,1);1];
 
        
        %calculate the dirsed angular orientation next step
        for i=1:N
                       
                       ubdi=omega_max*iself_count(i)/2; %upper bound
                       r=omega_max*iself_count(i); % the prediciton range of neighbors' motion
                       gVimid(i)=1/4*(i_store(i,2)+2*robot_itheta_last(i)+i_store(i,1)); % the midepoint of i's guaranteed Voronoi set 
                  
                       errp=gVimid(i)-robot_itheta_last(i); 
                       abserrp=abs(gVimid(i)-robot_itheta_last(i));
                       proximity=max(abserrp,self_tolerance); % the degree agent goes towards midpoint of its guaranteed Voronoi set
                       
                       % initially, set condition ubdi==0 to make robot
                       % communicate with its neighbors
                       if ((ubdi==0)||(ubdi>=proximity)||(i_store(i,2)-r<=robot_itheta_last(i))||(i_store(i,2)+r>=robot_itheta_last(i)))
                             %if (ubdi>=proximity)    
                             i_store(i,:)=[robot_theta_last(i),robot_theta_last(i+2)];% update the stored memory of its neighbors
                             pose_x_store((3*i-2):3*i,1)=robot_pose_px_enl(i:i+2,1);
                             pose_y_store((3*i-2):3*i,1)=robot_pose_py_enl(i:i+2,1);
                             
                             iself_count(i)=1; % reset the number of omega*T

                            %itheta(i,k+1)=itheta(i,k)+1/4*T*(theta(i+2,k)-2*theta(i+1,k)+theta(i,k));
                            utemp_angle=i_store(i,2)-2*robot_theta_last(i+1)+i_store(i,1);

                            u_angle_abs=min(omega_max,abs(1/4*utemp_angle));
                            u_angle_sign=sign(utemp_angle);
                            [linear_vel, angle_vel]=edge_vd_cmd(robot_pose_last,i,u_angle_abs,u_angle_sign);
                            
                            %update estimate of target if acquire new info from its neighbors 
                            [tarx_hat(i), tary_hat(i), Sigma_hat((2*i-1):2*i,:), tarxtrue,tarytrue] = KF_pioneer (...
                            tarx_hat(i), tary_hat(i), Sigma_hat((2*i-1):2*i,:), pose_x_store((3*i-2):3*i,1), pose_y_store((3*i-2):3*i,1),idb(i:(i+2)), timer_cnt);
                           
            
                       else
                             %R(2*i-1:2*i,k+1)=R(2*i-1:2*i,k); %keep memory
                              [tarx_hat(i), tary_hat(i), Sigma_hat((2*i-1):2*i,:), tarxtrue,tarytrue] = KF_pioneer (...
                            tarx_hat(i), tary_hat(i), Sigma_hat((2*i-1):2*i,:), robot_pose_px(i), robot_pose_py(i),id(i), timer_cnt);
                             
                              iself_count(i)= iself_count(i)+1;
             
                             if (abserrp>=ubdi+omega_max)
                             u_angle_abs=abs(omega_max);
                             elseif (abserrp<=ubdi)
                             u_angle_abs=0;
                             else
                             u_angle_abs=abs(abserrp-ubdi); 
                             end
                             u_angle_sign=sign(errp);
                             [linear_vel, angle_vel]=edge_vd_cmd(robot_pose_last,i,u_angle_abs,u_angle_sign);
                 
                       end     
                         timer_cnt=timer_cnt+1; 
                         robot_pub_msg.Linear.X=linear_vel;
                         robot_pub_msg.Angular.Z=angle_vel;
                         send(robot_pub_vel(i,:),robot_pub_msg);
        end
                         %publish target vel_cmd
                         target_pub_msg.Linear.X=0.1;
                         target_pub_msg.Angular.Z=0.05;
                         send(target_pub_vel,target_pub_msg);
                         
                         %plot the boundary, robot, target
                         cla; hold on;axis equal
                            p1x=[2.68 -3.7];
                            p1y=[10.9 1.39];
                            line(p1x,p1y), hold on

                            p2x=[-3.7 -2.56];
                            p2y=[1.39 -8.5];
                            line(p2x,p2y), hold on

                            p3x=[-2.56 7.38];
                            p3y=[-8.5 -0.688];
                            line(p3x,p3y), hold on

                            p4x=[7.38 2.68];
                            p4y=[-0.688 10.9];
                            line(p4x,p4y), hold on
                         
                         for i = 1 : size(robot_itheta_last,1)
                         %figure(2);
                         %h(1) = covarianceEllipse([x_hat;y_hat],Sigma_hat,[1 0 0],11.82);
                         %h(2) = plot(x_hat,y_hat,'rs','MarkerSize',8);
                         %h(3) = plot(x_true,y_true,'bp','MarkerSize',8);
                           h(1)=plot(robot_pose_px(i,1), robot_pose_py(i,1),'ro','MarkerFaceColor','r');
                           h(2) = covarianceEllipse([tarx_hat(i);tary_hat(i)],Sigma_hat((2*i-1):2*i,:),[1 0 0],11.82);
                           h(3)=plot(tarx_hat(i),tary_hat(i),'rs','MarkerSize',8);
                           h(4)=plot(tarxtrue,tarytrue,'bp','MarkerSize',8);
                           h(5)=plot ([robot_pose_px(i,1) tarx_hat(i)], [robot_pose_py(i,1) tary_hat(i)],':');
                         end               
end    