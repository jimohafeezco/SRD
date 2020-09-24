%This class provides user interface for general SRD functionality. Its
%purpose is to hide unnesessary details, make end-user code cleaner.
classdef SRDuserinterface < handle
    properties
        
        AnimateRobot = true;
        %determines if the robot will be animated when appropriate
        
        FileName_LinkArray               = 'datafile_LinkArray.mat';
        FileName_AxisLimits              = 'datafile_AxisLimits.mat';
        FileName_ViewAngle               = 'datafile_ViewAngle.mat';
        FileName_SymbolicEngine          = 'datafile_SymbolicEngine.mat';
        FileName_SimulationEngine        = 'datafile_SimulationEngine.mat';
        FileName_InverseKinematicsEngine = 'datafile_InverseKinematicsEngine.mat';
        FileName_InitialPosition         = 'datafile_InitialPosition.mat';
        
    end
    methods
        function obj = SRDuserinterface(UseParallelizedSimplification, NumberOfWorkers)
            if nargin < 1
                UseParallelizedSimplification = [];
            end
            if ~isempty(UseParallelizedSimplification)
                obj.UseParallelizedSimplification = UseParallelizedSimplification;
            end
            
            if nargin < 2
                NumberOfWorkers = [];
            end
            if ~isempty(NumberOfWorkers)
                obj.NumberOfWorkers = NumberOfWorkers;
            end
                
        end
       
        function Ground = CreateGroundLink(~)
            RelativeBase = [0; 0; 0];
            RelativeFollower = [0; 0; 0];
            RelativeCoM = [0; 0; 0];
            Mass = 0;
            Inertia = eye(3);
            Name = 'Ground';
            save('datafile_ground', 'RelativeBase', 'RelativeFollower', 'RelativeCoM', 'Mass', 'Inertia', 'Name');
            rehash;
            
            Ground = SRDLinkWithJoint('none', 0, 'datafile_ground', [], []);
            Ground.RelativeOrientation = eye(3);
        end
        
        % This function creates an SRD object that will be used for
        % simulation.
        % LinkArray - an array of links, objects of the class
        % SRDLinkWithJoint. User needs to assign them their generalized
        % coordinates before passing them here (using
        % .SetUsedGenCoordinates method of SRDLinkWithJoint class)
        %
        % InitialPosition - initial value of the vector of the generalized
        % coordinates
        %
        % AxisLimits - defines the limits for the axes
        % ViewAngle - defines the camera view angle
        function CreateRobotStructure(obj, LinkArray, InitialPosition, AxisLimits, ViewAngle,DrawFrames,DrawMeshes)
            
            if nargin < 4
                AxisLimits = [];
            end
            if isempty(AxisLimits)
                AxisLimits = [-1; 1; -1; 1; -1; 1];
            end
            
            if nargin < 5
                ViewAngle = [];
            end
            if isempty(ViewAngle)
                ViewAngle = [-37.5, 30];
            end
            
            %Save LinkArray
            save(obj.FileName_LinkArray, 'LinkArray');
            %Save AxisLimits
            save(obj.FileName_AxisLimits, 'AxisLimits');
            %Save ViewAngle
            save(obj.FileName_ViewAngle, 'ViewAngle');
            
            %We create SimulationEngine, it will be used for simulation and
            %other things
            SimulationEngine = SRDSimulationEngine(LinkArray);
            
            %Pass InitialPosition to SimulationEngine and also save it
            SimulationEngine.IC.q = InitialPosition;
            obj.SaveInitialPosition(InitialPosition);
            
            %Update the mechanism, so it will take initial configuration
            SimulationEngine.Update(InitialPosition);
            obj.SaveSimulationEngine(SimulationEngine);
            
            rehash;
            
            if obj.AnimateRobot
                %Display the initial position of the mechanism
                Animation = SRDAnimation();
                Animation.DrawFrames = DrawFrames;
                if DrawMeshes
                    Animation.DrawType = 'STL';
                end
                Animation.DrawIC();
                xlabel('x axis'); ylabel('y axis'); zlabel('z axis');
            end
        end
        
        %This function needs .CreateRobotStructure to have been called.
        %
        %dissipation_coefficients - pass vector to assign each
        %individually, a scalar to assign them uniformly, or nothing to
        %have them all set as 1
        function SymbolicEngine = DeriveEquationsForSimulation(obj, varargin)
            Parser = inputParser;
            Parser.FunctionName = 'DeriveEquationsForSimulation';
            Parser.addOptional('UseCasadi', false);
            Parser.addOptional('ToLinearize', false);     
            Parser.addOptional('ToSimplify', true);  
            Parser.addOptional('dissipation_coefficients', []); 
            Parser.addOptional('ToRecreateSymbolicEngine', true);
            %if true - method will create new SymbolicEngine; 
            %if false, the method will attempt to load usiting engine;
            
            Parser.addOptional('ToSaveSymbolicEngine', true);  
            
            Parser.addOptional('NumberOfWorkers', 8); 
            %Defines the number of MATLAB workers that will be used in 
            %parallel computing
            
            Parser.addOptional('ToUseParallelizedSimplification', false); 
            %If true, the programm will simplify the elements of symbolic 
            %vector expressions in parallel and it will report the progress
            
            Parser.addOptional('ToOptimizeFunctions', true); 
            %This property will be used to set the same property of the
            %SymbolicEngine
            
            
            Parser.parse(varargin{:});
            
            %load created previously LinkArray 
            LinkArray = obj.GetLinkArray;
            
            %Create SymbolicEngine that will be used for deriving equations
            if Parser.Results.ToRecreateSymbolicEngine
                SymbolicEngine = SRDSymbolicEngine(LinkArray, Parser.Results.UseCasadi);
            else
                SymbolicEngine = obj.GetSymbolicEngine(true);
                if isempty(SymbolicEngine)
                    SymbolicEngine = SRDSymbolicEngine(LinkArray);
                end
            end
            
            %if UseParallelizedSimplification or NumberOfWorkers properties
            %are defined, pass them to the SymbolicEngine
            SymbolicEngine.UseParallelizedSimplification = Parser.Results.ToUseParallelizedSimplification;
            SymbolicEngine.NumberOfWorkers = Parser.Results.NumberOfWorkers;
            SymbolicEngine.ToOptimizeFunctions = Parser.Results.ToOptimizeFunctions;
            
            %Assignment of the dissipation cefficients
            if isempty(Parser.Results.dissipation_coefficients)
                SymbolicEngine.dissipation_coefficients = ones(SymbolicEngine.dof, 1);
            else
                if length(Parser.Results.dissipation_coefficients) == 1
                    SymbolicEngine.dissipation_coefficients = Parser.Results.dissipation_coefficients * ones(SymbolicEngine.dof, 1);
                else
                    SymbolicEngine.dissipation_coefficients = Parser.Results.dissipation_coefficients;
                end
            end
            
            %Create dynamics eq. 
            SymbolicEngine.BuildDynamicsEquations(Parser.Results.ToSimplify, false);
            %Generate nesessary function from those equations
            if Parser.Results.UseCasadi
                SymbolicEngine.GenerateForwardDynamicsFunctions_Casadi();
            else
                SymbolicEngine.GenerateForwardDynamicsFunctions();
            end
            
            %If requested generate linearized version of dynamics eq
            if Parser.Results.ToLinearize
                SymbolicEngine.DoLinearization(Parser.Results.ToSimplify);
            end
            
            if Parser.Results.ToSaveSymbolicEngine
                obj.SaveSymbolicEngine(SymbolicEngine);
            end
            rehash;            
        end
        
        %Task - symbolic expression of the inverse kinematics task
        function InverseKinematicsEngine = SetupSymbolicInverseKinematics(obj, varargin)
            Parser = inputParser;
            Parser.FunctionName = 'SRDuserinterface.SetupSymbolicInverseKinematics';
            Parser.addOptional('Task', []);
            Parser.addOptional('SymbolicEngine', []);
            Parser.addOptional('ToSaveInverseKinematicsEngine', true);
            Parser.parse(varargin{:});
            
            if isempty(Parser.Results.SymbolicEngine)
                SymbolicEngine = obj.GetSymbolicEngine();
            else
                SymbolicEngine = Parser.Results.SymbolicEngine;
            end
            
            %create InverseKinematicsEngine
            InverseKinematicsEngine = SRDInverseKinematics;
            %derive nessesary symbolic functions
            InverseKinematicsEngine.IKsetup(SymbolicEngine, Parser.Results.Task);
            
            if Parser.Results.ToSaveInverseKinematicsEngine
                obj.SaveInverseKinematicsEngine(InverseKinematicsEngine);
            end
            rehash;
        end
        
        %This function solves inverse kinematics problem numerically,
        %and approximates the solution. SetupSymbolicInverseKinematics
        %needs to have been called.
        %
        %DesiredTask - fuction handle, the output needs to match dimentions
        %of Task, the input of .SetupSymbolicInverseKinematics() called
        %earlier.
        function SetupNumericInverseKinematics(obj, varargin)
            Parser = inputParser;
            Parser.FunctionName = 'SRDuserinterface.SetupNumericInverseKinematics';
            Parser.addOptional('DesiredTask', []);
            Parser.addOptional('TimeRange', []);
            Parser.addOptional('PolynomialDegree', 5);
            Parser.addOptional('NumberOfSegments', []);
            Parser.addOptional('SolverType', 'lsqnonlin');
            Parser.addOptional('LookupTableTimeStep', 0.001);
            Parser.addOptional('TimeStep', 0.01);
            Parser.addOptional('problem', []);
            Parser.addOptional('ToPlot', true);
            Parser.addOptional('Verbose', true);
            Parser.parse(varargin{:});
            
            %load created previously InverseKinematicsEngine
            FileName = 'datafile_InverseKinematicsEngine.mat';
            if exist(FileName, 'file') == 2
                temp = load(FileName);
                InverseKinematicsEngine = temp.InverseKinematicsEngine;
            else
                error(['File ', FileName, ' does not exist. Create the inverse kinematics engine before using it']);
            end
            
            %%%%%%%%%%%%%%%%%
            %input parameters processing
            if isempty(Parser.Results.DesiredTask)
                error('provide DesiredTask')
            end
            
            TimeRange = Parser.Results.TimeRange;
            if ~isempty(TimeRange)
                %give time range for inverse kinematics problem
                InverseKinematicsEngine.TimeStart = TimeRange(1);
                InverseKinematicsEngine.TimeEnd = TimeRange(2);
            end
            
            NumberOfSegments = Parser.Results.NumberOfSegments;
            if isempty(NumberOfSegments)
                NumberOfSegments = floor((TimeRange(2) - TimeRange(1)) / ...
                    (2 * Parser.Results.PolynomialDegree * InverseKinematicsEngine.dt));
            end
            %%%%%%%%%%%%%%%%%
            
            
            %load InitialPosition and pass it to InverseKinematicsEngine
            InverseKinematicsEngine.InitialGuess = obj.GetInitialPosition();
            
            %set IK solver type
            if ~isempty(Parser.Results.SolverType)
                InverseKinematicsEngine.SolverType = Parser.Results.SolverType;
            end
            
            %set IK time step
            InverseKinematicsEngine.dt = Parser.Results.TimeStep;
            
            %Solve the inverse kinematics problem
            if Parser.Results.Verbose; disp('Called .SolveAndApproximate procedure'); end
            InverseKinematicsEngine.SolveAndApproximate(Parser.Results.DesiredTask, ...
                Parser.Results.PolynomialDegree, NumberOfSegments, Parser.Results.problem);
            
            if Parser.Results.LookupTableTimeStep ~= 0
                InverseKinematicsEngine.LookupTable_dt = Parser.Results.LookupTableTimeStep;
                
                if Parser.Results.Verbose; disp('Called .GenerateLookupTable procedure'); end
                InverseKinematicsEngine.GenerateLookupTable;
            end
            
            %save the solution
            save('datafile_InverseKinematicsEngine_processed', 'InverseKinematicsEngine');
            
            %plot the solution
            if Parser.Results.ToPlot
                InverseKinematicsEngine.PlotGraphsFromEvaluatePolynomialApproximation;
            end
        end
            
        %loads LinkArray from a file
        function LinkArray = GetLinkArray(obj)
            if exist(obj.FileName_LinkArray, 'file') == 2
                %load created previously LinkArray 
                temp = load(obj.FileName_LinkArray);
                LinkArray = temp.LinkArray;
            else
                warning(['File ', obj.FileName_LinkArray, ' does not exist. Create the LinkArray before using it']);
                LinkArray = [];
            end
        end       
        
        %loads SymbolicEngine from a file
        function SymbolicEngine = GetSymbolicEngine(obj, SilentMode)
            
            if nargin < 2
                SilentMode = false;
            end
            
            if exist(obj.FileName_SymbolicEngine, 'file') == 2
                %load created previously SymbolicEngine
                temp = load(obj.FileName_SymbolicEngine);
                SymbolicEngine = temp.SymbolicEngine;
                if ~SymbolicEngine.Casadi
                    SymbolicEngine.SetAssumptions();
                end
            else
                if ~SilentMode
                    warning(['File ', obj.FileName_SymbolicEngine, ' does not exist. Set up the symbolic engine before using it']);
                end
                SymbolicEngine = [];
            end
        end
        
        %creates new SymbolicEngine
        %set ToUpdateGeometry = true if need to use .GeometryArray field of
        %the SymbolicEngine
        function SymbolicEngine = GetNewSymbolicEngine(obj, ToUpdateGeometry)
            
            if nargin < 2
                ToUpdateGeometry = false;
            end
            
            %load created previously LinkArray 
            LinkArray = obj.GetLinkArray;
            SymbolicEngine = SRDSymbolicEngine(LinkArray);
            
            %if UseParallelizedSimplification or NumberOfWorkers properties
            %are defined, pass them to the SymbolicEngine
            if ~isempty(obj.UseParallelizedSimplification)
                SymbolicEngine.UseParallelizedSimplification = obj.UseParallelizedSimplification;
            end
            if ~isempty(obj.NumberOfWorkers)
                SymbolicEngine.NumberOfWorkers = obj.NumberOfWorkers;
            end            
            
            %if requested - udate .GeometryArray field in the SymbolicEngine
            if ToUpdateGeometry
                SymbolicEngine.UpdateGeometryArray(true);
            end
        end
        
        %loads SimulationEngine from a file
        %PutIntoInitialPosition - if true, the mechanism will be put into
        %its original position, as defined in the file
        %datafile_InitialPosition. It is not nesessary, as the mechanism
        %should be in that position already if the default procedure for
        %setting it up was used
        function SimulationEngine = GetSimulationEngine(obj, PutIntoInitialPosition)
            
            if nargin < 2
                PutIntoInitialPosition = false;
            end
            
            if exist(obj.FileName_SimulationEngine, 'file') == 2
                %load created previously SimulationEngine
                temp = load(obj.FileName_SimulationEngine);
                SimulationEngine = temp.SimulationEngine;
                
                %if requested put the mechanism into its initial position.
                if PutIntoInitialPosition
                    InitialPosition = obj.GetInitialPosition();
                    SimulationEngine.IC.q = InitialPosition;
                    SimulationEngine.Update(InitialPosition);
                end
                
                %if the control dof are not calculated for SimulationEngine
                %- attempt to load the info from the file
                TryToLoad_Control_dof = false;
                if ~isfield(SimulationEngine, 'Control_dof')
                    TryToLoad_Control_dof = true;
                else
                    if isempty(SimulationEngine.Control_dof)
                        TryToLoad_Control_dof = true;
                    end
                end
                if TryToLoad_Control_dof
                    FileName_Control_dof = 'datafile_settings_Control_dof.mat';
                    if exist(FileName_Control_dof, 'file') == 2
                        temp = load(FileName_Control_dof);
                        SimulationEngine.Control_dof = temp.Control_dof;
                    end
                end
                
                SimulationEngine.Initialization;
            else
                warning(['File ', obj.FileName_SimulationEngine, ' does not exist. Set up the simulation engine before using it']);
                SimulationEngine = [];
            end
        end
        
        %loads InitialPosition from a file
        function InitialPosition = GetInitialPosition(obj)
            if exist(obj.FileName_InitialPosition, 'file') == 2
                %load created previously InitialPosition
                temp = load(obj.FileName_InitialPosition);
                InitialPosition = temp.InitialPosition;
            else
                warning(['File ', obj.FileName_InitialPosition, ' does not exist. Define the initial position before using it']);
                InitialPosition = [];
            end
        end
        
        %loads InverseKinematicsEngine from a file
        function InverseKinematicsEngine = GetInverseKinematicsEngine(~)
            FileName = 'datafile_InverseKinematicsEngine_processed.mat';
            if exist(FileName, 'file') == 2
                %load created previously InverseKinematicsEngine with the
                %solved IK problem
                temp = load(FileName);
                InverseKinematicsEngine = temp.InverseKinematicsEngine;
            else
                warning(['File ', FileName, ...
                    ' does not exist. Set up and process the inverse kinematics engine before using it']);
                InverseKinematicsEngine = [];
            end
        end
        
        
        %loads ExternalForcesEngine from a file
        function ExternalForcesEngine = GetExternalForcesEngine(~)
            FileName = 'datafile_ExternalForcesEngine.mat';
            if exist(FileName, 'file') == 2
                %load created previously InverseKinematicsEngine with the
                %solved IK problem
                temp = load(FileName);
                ExternalForcesEngine = temp.ExternalForcesEngine;
            else
                warning(['File ', FileName, ...
                    ' does not exist. Set up and process the External Forces Engine before using it']);
                ExternalForcesEngine = [];
            end
        end
        
        %loads AxisLimits from a file
        function AxisLimits = GetAxisLimits(obj)
            if exist(obj.FileName_AxisLimits, 'file') == 2
                %load created saved previously AxisLimits
                temp = load(obj.FileName_AxisLimits);
                AxisLimits = temp.AxisLimits;
            else
                warning(['File ', obj.FileName_AxisLimits, ' does not exist']);
                AxisLimits = [];
            end
        end
        
        %loads AxisLimits from a file
        function ViewAngle = GetViewAngle(obj)
            if exist(obj.FileName_ViewAngle, 'file') == 2
                %load created saved previously ViewAngle
                temp = load(obj.FileName_ViewAngle);
                ViewAngle = temp.ViewAngle;
            else
                warning(['File ', obj.FileName_ViewAngle, ' does not exist']);
                ViewAngle = [];
            end
        end
        
        %saves SymbolicEngine
        function SaveSymbolicEngine(obj, SymbolicEngine)            
            save(obj.FileName_SymbolicEngine, 'SymbolicEngine');
        end
        
        %saves SimulationEngine
        function SaveSimulationEngine(obj, SimulationEngine)
            save(obj.FileName_SimulationEngine, 'SimulationEngine');
        end
        
        %saves InverseKinematicsEngine
        function SaveInverseKinematicsEngine(obj, InverseKinematicsEngine)
            save(obj.FileName_InverseKinematicsEngine, 'InverseKinematicsEngine');
        end
        
        %saves SimulationEngine
        function SaveInitialPosition(obj, InitialPosition)
            save(obj.FileName_InitialPosition, 'InitialPosition');
        end
        
        %saves SimulationEngine
        function SaveExternalForcesEngine(~, ExternalForcesEngine)
            FileName = 'datafile_ExternalForcesEngine.mat';
            save(FileName, 'ExternalForcesEngine');
        end
        
    end
end